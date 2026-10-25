// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

/// One planned step, as a host lists it.
package struct BenchmarkListEntry: Sendable, Equatable, Codable {
  /// The step's stable identifier, which `measure --step` selects.
  package var id: String
  package var suite: String
  package var caseName: String
  package var tags: [String]
  package var arguments: [Benchmark.ArgumentValue]
  package var dimensionSizes: [Int]

  /// Creates an entry.
  package init(
    id: String,
    suite: String,
    caseName: String,
    tags: [String] = [],
    arguments: [Benchmark.ArgumentValue] = [],
    dimensionSizes: [Int] = []
  ) {
    self.id = id
    self.suite = suite
    self.caseName = caseName
    self.tags = tags
    self.arguments = arguments
    self.dimensionSizes = dimensionSizes
  }
}

/// The steps a host plans to measure, with the metadata of its process.
package struct HostPlan: Sendable, Codable {
  package var metadata: RunMetadata
  package var steps: [BenchmarkListEntry]

  package init(metadata: RunMetadata, steps: [BenchmarkListEntry]) {
    self.metadata = metadata
    self.steps = steps
  }
}

/// What one host process measured: the run's event records with the
/// metadata of the process that produced them.
package struct HostMeasurement: Sendable, Codable {
  package var metadata: RunMetadata
  package var records: [Benchmark.Event.Stream.Record]
  package var attributions: [TimelineAttribution]

  package init(
    metadata: RunMetadata,
    records: [Benchmark.Event.Stream.Record],
    attributions: [TimelineAttribution] = []
  ) {
    self.metadata = metadata
    self.records = records
    self.attributions = attributions
  }
}

/// The executable the package workflow measures in.
///
/// The command plugin generates a host for the package's declarations. To
/// measure declarations that only an executable target can reach, call
/// ``run(discoveries:arguments:metadata:)`` from that executable's `main`
/// and pass the executable to the CLI with `--host`. The CLI asks the host
/// for its plan, then measures each step in a host process of its own;
/// comparison, gating and rendering stay in the CLI.
public enum BenchmarkHost {
  /// Answers the CLI's request in `arguments` for the benchmarks that
  /// `discoveries` declare. Errors are written to standard error and exit
  /// the process with status 1.
  public static func run(
    discoveries: [any _BenchmarkDiscovery.Type],
    arguments: [String] = Array(CommandLine.arguments.dropFirst()),
    metadata: RunMetadata = .local(id: "run:benchmark-host")
  ) async {
    do {
      let (output, path) = try await execute(
        discoveries: discoveries, arguments: arguments, metadata: metadata)
      if let path {
        try output.write(to: URL(fileURLWithPath: path))
      } else {
        FileHandle.standardOutput.write(output)
      }
    } catch {
      FileHandle.standardError.write(Data("benchmark-host: \(error)\n".utf8))
      exit(1)
    }
  }

  /// The JSON the host command in `arguments` produces: a `HostPlan` for
  /// `list`, and a `HostMeasurement` for `measure`.
  package static func output(
    discoveries: [any _BenchmarkDiscovery.Type],
    arguments: [String],
    metadata: RunMetadata = .local(id: "run:benchmark-host")
  ) async throws -> Data {
    try await execute(discoveries: discoveries, arguments: arguments, metadata: metadata).output
  }

  private static func execute(
    discoveries: [any _BenchmarkDiscovery.Type],
    arguments: [String],
    metadata: RunMetadata
  ) async throws -> (output: Data, path: String?) {
    guard let command = arguments.first else {
      throw BenchmarkHostError.unknownCommand("")
    }
    let options = try BenchmarkHostOptions(Array(arguments.dropFirst()))
    let plan = try options.plan(discoveries: discoveries)
    guard !plan.steps.isEmpty else {
      throw BenchmarkHostError.noBenchmarksSelected
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    switch command {
    case "list":
      let steps = plan.steps.map { step in
        BenchmarkListEntry(
          id: step.id,
          suite: step.suiteName,
          caseName: step.caseName,
          tags: step.tags,
          arguments: step.arguments,
          dimensionSizes: step.size.map { [$0.rawValue] } ?? []
        )
      }
      return (try encoder.encode(HostPlan(metadata: metadata, steps: steps)), options.outputPath)
    case "measure":
      if options.isolated, plan.steps.count != 1 {
        throw BenchmarkHostError.isolatedSelection(plan.steps.map(\.id))
      }
      let measurement = try await measure(
        plan,
        metadata: metadata,
        capturesTimeline: options.capturesTimeline,
        isolated: options.isolated
      )
      return (try encoder.encode(measurement), options.outputPath)
    default:
      throw BenchmarkHostError.unknownCommand(command)
    }
  }

  private static func measure(
    _ plan: BenchmarkRunner.Plan,
    metadata: RunMetadata,
    capturesTimeline: Bool,
    isolated: Bool
  ) async throws -> HostMeasurement {
    let timelineObserver = capturesTimeline ? BenchmarkTimelineObserver() : nil
    let events = Benchmark.Event.InMemoryRecorder()
    let results = try await BenchmarkRunner(recordsPeakMemory: isolated).run(
      plan,
      observers: timelineObserver.map { [$0] } ?? [],
      eventRecorders: [events]
    )
    let attributions =
      timelineObserver.map {
        TimelineCorrelator.attributions(
          from: $0.recorder.snapshot(), runID: metadata.id, results: results)
      } ?? []
    return HostMeasurement(
      metadata: metadata, records: await events.snapshot(), attributions: attributions)
  }
}

package enum BenchmarkHostError: Error, CustomStringConvertible {
  case unknownCommand(String)
  case unexpectedArgument(String)
  case missingValue(String)
  case invalidNumber(String, String)
  case unknownStep(String)
  /// `--isolated` selected these steps instead of exactly one.
  case isolatedSelection([String])
  case noBenchmarksSelected

  package var description: String {
    switch self {
    case .unknownCommand(let command):
      return "Unknown benchmark host command '\(command)'; use list or measure."
    case .unexpectedArgument(let argument):
      return "Unexpected argument '\(argument)'."
    case .missingValue(let option):
      return "Missing value for \(option)."
    case .invalidNumber(let option, let value):
      return "Invalid number '\(value)' for \(option)."
    case .unknownStep(let id):
      return "No planned step has the identifier '\(id)'."
    case .isolatedSelection(let ids):
      return
        "--isolated measures exactly one step, but the selection has \(ids.count): \(ids.joined(separator: ", "))."
    case .noBenchmarksSelected:
      return "No benchmarks matched the requested filters."
    }
  }
}

/// The host's arguments: step selection, configuration overrides, and where
/// to write the output.
private struct BenchmarkHostOptions {
  private static let flags: Set<String> = ["--adaptive", "--isolated", "--timeline"]
  private static let valueOptions: Set<String> = [
    "--suite", "--case", "--tag", "--step", "--output",
    "--warmup", "--iterations", "--batch-size",
    "--min-iterations", "--max-iterations", "--min-duration-ns", "--max-duration-ns",
  ]

  private var values: [String: [String]] = [:]
  private var flags: Set<String> = []

  init(_ arguments: [String]) throws {
    var index = arguments.startIndex
    while index < arguments.endIndex {
      let key = arguments[index]
      if Self.flags.contains(key) {
        flags.insert(key)
        index += 1
        continue
      }
      guard Self.valueOptions.contains(key) else {
        throw BenchmarkHostError.unexpectedArgument(key)
      }
      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex, !arguments[valueIndex].hasPrefix("--") else {
        throw BenchmarkHostError.missingValue(key)
      }
      values[key, default: []].append(arguments[valueIndex])
      index = arguments.index(after: valueIndex)
    }
  }

  var outputPath: String? {
    values["--output"]?.last
  }

  var capturesTimeline: Bool {
    flags.contains("--timeline")
  }

  /// Whether this process measures nothing but the selected step, which
  /// makes its peak memory attributable to that step.
  var isolated: Bool {
    flags.contains("--isolated")
  }

  func plan(discoveries: [any _BenchmarkDiscovery.Type]) throws -> BenchmarkRunner.Plan {
    let filter = BenchmarkRunner.Plan.Filter(
      suiteName: values["--suite"]?.last,
      caseName: values["--case"]?.last,
      tags: values["--tag"] ?? []
    )
    var plan = try BenchmarkDiscovery(discoveries).plan(filter: filter)
    if let stepIDs = values["--step"] {
      let known = Set(plan.steps.map(\.id))
      if let unknown = stepIDs.first(where: { !known.contains($0) }) {
        throw BenchmarkHostError.unknownStep(unknown)
      }
      plan.steps = plan.steps.filter { stepIDs.contains($0.id) }
    }
    plan.steps = try plan.steps.map { step in
      var step = step
      step.configuration = try configuration(overriding: step.configuration)
      return step
    }
    return plan
  }

  private func configuration(overriding configuration: BenchmarkConfiguration) throws
    -> BenchmarkConfiguration
  {
    BenchmarkConfiguration(
      warmup: try warmup(default: configuration.warmup),
      iterations: try iterations(default: configuration.iterations),
      batching: try intValue(for: "--batch-size").map(BatchingPolicy.fixed)
        ?? configuration.batching
    )
  }

  private func warmup(default defaultPolicy: WarmupPolicy) throws -> WarmupPolicy {
    guard let count = try intValue(for: "--warmup") else {
      return defaultPolicy
    }
    return count == 0 ? .none : .iterations(count)
  }

  private func iterations(default defaultPolicy: IterationPolicy) throws -> IterationPolicy {
    let minDuration = try uint64Value(for: "--min-duration-ns")
    let maxDuration = try uint64Value(for: "--max-duration-ns")
    let minIterations = try intValue(for: "--min-iterations")
    let maxIterations = try intValue(for: "--max-iterations")
    let fixedIterations = try intValue(for: "--iterations")
    if flags.contains("--adaptive") || minDuration != nil || maxDuration != nil
      || minIterations != nil || maxIterations != nil
    {
      return .adaptive(
        minIterations: minIterations ?? 1,
        maxIterations: maxIterations ?? fixedIterations ?? 100,
        minDurationNanoseconds: minDuration,
        maxDurationNanoseconds: maxDuration
      )
    }
    return fixedIterations.map(IterationPolicy.iterations) ?? defaultPolicy
  }

  private func intValue(for key: String) throws -> Int? {
    guard let value = values[key]?.last else {
      return nil
    }
    guard let integer = Int(value) else {
      throw BenchmarkHostError.invalidNumber(key, value)
    }
    return integer
  }

  private func uint64Value(for key: String) throws -> UInt64? {
    guard let value = values[key]?.last else {
      return nil
    }
    guard let integer = UInt64(value) else {
      throw BenchmarkHostError.invalidNumber(key, value)
    }
    return integer
  }
}
