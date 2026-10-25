// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

public struct BenchmarkListEntry: Sendable, Equatable, Codable {
  public var suite: String
  public var caseName: String
  public var tags: [String]
  public var arguments: [Benchmark.ArgumentValue]
  public var dimensionSizes: [Int]

  public init(
    suite: String,
    caseName: String,
    tags: [String] = [],
    arguments: [Benchmark.ArgumentValue] = [],
    dimensionSizes: [Int] = []
  ) {
    self.suite = suite
    self.caseName = caseName
    self.tags = tags
    self.arguments = arguments
    self.dimensionSizes = dimensionSizes
  }
}

public enum BenchmarkHost {
  package static let regressionFailureExitStatus: Int32 = 20

  public static func run(
    discoveries: [any _BenchmarkDiscovery.Type],
    arguments: [String] = Array(CommandLine.arguments.dropFirst()),
    metadata: RunMetadata = .local(id: "run:benchmark-host")
  ) async throws {
    let output: String
    do {
      output = try await render(
        discoveries: discoveries, arguments: arguments, metadata: metadata)
    } catch BenchmarkHostError.regressionFailure(let report) {
      if !report.isEmpty {
        print(report)
      }
      exit(regressionFailureExitStatus)
    }
    if !output.isEmpty {
      print(output)
    }
  }

  public static func render(
    discoveries: [any _BenchmarkDiscovery.Type],
    arguments: [String],
    metadata: RunMetadata = .local(id: "run:benchmark-host")
  ) async throws -> String {
    guard let command = arguments.first else {
      return help()
    }

    let options = try BenchmarkHostOptions(Array(arguments.dropFirst()))
    let discovery = BenchmarkDiscovery(discoveries)
    let filter = BenchmarkRunner.Plan.Filter(
      suiteName: options.value(for: "--suite"),
      caseName: options.value(for: "--case"),
      tags: options.values(for: "--tag")
    )
    var plan = try discovery.plan(filter: filter)
    plan.steps = try plan.steps.map { step in
      var step = step
      step.configuration = try options.configuration(overriding: step.configuration)
      return step
    }

    switch command {
    case "help", "--help", "-h":
      return help()
    case "list":
      let entries = plan.steps.map { step in
        BenchmarkListEntry(
          suite: step.suiteName,
          caseName: step.caseName,
          tags: step.tags,
          arguments: step.arguments,
          dimensionSizes: step.size.map { [$0.rawValue] } ?? []
        )
      }
      guard !entries.isEmpty else {
        throw BenchmarkHostError.noBenchmarksSelected
      }
      if try options.format(default: .console) == .json {
        return try encodeJSON(entries)
      }
      return entries.map { entry in
        let tags = entry.tags.isEmpty ? "" : " tags=\(entry.tags.joined(separator: ","))"
        let arguments =
          entry.arguments.isEmpty
          ? ""
          : " arguments=\(entry.arguments.map(\.label).joined(separator: ","))"
        let suffix = entry.dimensionSizes.isEmpty ? "" : " size=\(entry.dimensionSizes[0])"
        return "\(entry.suite).\(entry.caseName)\(tags)\(arguments)\(suffix)"
      }.joined(separator: "\n")
    case "run", "check", "trace":
      guard !plan.steps.isEmpty else {
        throw BenchmarkHostError.noBenchmarksSelected
      }
      if command == "check" {
        try CheckGate.validate(
          buildConfiguration: metadata.buildConfiguration,
          allowDebug: options.hasFlag("--allow-debug"))
      }
      let baseline = try options.value(for: "--baseline").map(BaselineDocument.read(path:))
      let format = try options.format(default: .console)
      let document = try await BenchmarkCommand().report(
        plan: plan,
        metadata: metadata,
        baseline: baseline,
        comparison: try options.comparison(),
        timelineCapture: command == "trace" || options.hasFlag("--timeline")
          ? .benchmarkIterations : .disabled,
        metricProviders: options.metricProviders(),
        traceExporters: options.traceExporters(runID: metadata.id)
      )
      let emitted = try writeOrReturn(try format.render(document), options: options)
      if command == "check" {
        guard document.summary.failedRegressionCount == 0 && document.summary.failedBudgetCount == 0
        else {
          throw BenchmarkHostError.regressionFailure(output: emitted)
        }
      }
      return emitted
    default:
      throw BenchmarkHostError.unknownCommand(command)
    }
  }

  public static func help() -> String {
    """
    benchmark-host

    Commands:
      list [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json]
      run [--suite <name>] [--case <name>] [--tag <tag>] [--warmup <n>] [--iterations <n>] [--batch-size <n>] [--adaptive] [--min-duration-ns <n>] [--max-duration-ns <n>] [--format console|json|speedscope] [--baseline <path>] [--statistic <name>] [--threshold [<metric>=]<value>] [--budget <metric>:<statistic>:<value>] [--output <path>] [--trace <path>] [--required-trace <path>]
      check --baseline <path> [--allow-debug] [--suite <name>] [--case <name>] [--tag <tag>]
      trace [same options as run, with timeline capture enabled]
    """
  }

  private static func writeOrReturn(_ output: String, options: BenchmarkHostOptions) throws
    -> String
  {
    if let outputPath = options.value(for: "--output") {
      try output.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
      return options.hasFlag("--quiet") ? "" : output
    }
    return options.hasFlag("--quiet") ? "" : output
  }

  private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

public enum BenchmarkHostError: Error, CustomStringConvertible {
  case unknownCommand(String)
  case unexpectedArgument(String)
  case missingValue(String)
  case invalidFormat(String)
  case invalidNumber(String, String)
  case noBenchmarksSelected
  case regressionFailure(output: String)

  public var description: String {
    switch self {
    case .unknownCommand(let command):
      return "Unknown benchmark host command '\(command)'."
    case .unexpectedArgument(let argument):
      return "Unexpected argument '\(argument)'."
    case .missingValue(let option):
      return "Missing value for \(option)."
    case .invalidFormat(let format):
      return "Invalid format '\(format)'."
    case .invalidNumber(let option, let value):
      return "Invalid number '\(value)' for \(option)."
    case .noBenchmarksSelected:
      return "No benchmarks matched the requested filters."
    case .regressionFailure:
      return "Regression check failed."
    }
  }
}

private struct BenchmarkHostOptions {
  private static let flags: Set<String> = [
    "--adaptive",
    "--allow-debug",
    "--quiet",
    "--timeline",
  ]

  private var values: [String: [String]] = [:]
  private var flags: Set<String> = []

  init<S: Sequence>(_ arguments: S) throws where S.Element == String {
    let arguments = Array(arguments)
    var index = arguments.startIndex
    while index < arguments.endIndex {
      let key = arguments[index]
      guard key.hasPrefix("--") else {
        throw BenchmarkHostError.unexpectedArgument(key)
      }
      if Self.flags.contains(key) {
        flags.insert(key)
        index += 1
        continue
      }
      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex else {
        throw BenchmarkHostError.missingValue(key)
      }
      let value = arguments[valueIndex]
      guard !value.hasPrefix("--") else {
        throw BenchmarkHostError.missingValue(key)
      }
      values[key, default: []].append(value)
      index = arguments.index(after: valueIndex)
    }
  }

  func hasFlag(_ key: String) -> Bool {
    flags.contains(key)
  }

  func value(for key: String) -> String? {
    values[key]?.last
  }

  func values(for key: String) -> [String] {
    values[key] ?? []
  }

  func format(default defaultFormat: ReportFormat = .console) throws -> ReportFormat {
    guard let value = values["--format"]?.last else {
      return defaultFormat
    }
    guard let format = ReportFormat(rawValue: value) else {
      throw BenchmarkHostError.invalidFormat(value)
    }
    return format
  }

  func comparison() throws -> ComparisonPolicy {
    try ComparisonArguments.policy(
      statistic: value(for: "--statistic"),
      thresholds: values(for: "--threshold"),
      budgets: values(for: "--budget"),
      caseBudgets: values(for: "--case-budget")
    )
  }

  func configuration(overriding configuration: BenchmarkConfiguration) throws
    -> BenchmarkConfiguration
  {
    BenchmarkConfiguration(
      warmup: try warmup(default: configuration.warmup),
      iterations: try iterations(default: configuration.iterations),
      batching: try batching(default: configuration.batching)
    )
  }

  func batching(default defaultPolicy: BatchingPolicy) throws -> BatchingPolicy {
    guard let count = try intValue(for: "--batch-size") else {
      return defaultPolicy
    }
    return .fixed(count)
  }

  func warmup(default defaultPolicy: WarmupPolicy) throws -> WarmupPolicy {
    guard let value = value(for: "--warmup") else {
      return defaultPolicy
    }
    guard let count = Int(value) else {
      throw BenchmarkHostError.invalidNumber("--warmup", value)
    }
    return count == 0 ? .none : .iterations(count)
  }

  func iterations(default defaultPolicy: IterationPolicy) throws -> IterationPolicy {
    let minDuration = try uint64Value(for: "--min-duration-ns")
    let maxDuration = try uint64Value(for: "--max-duration-ns")
    let minIterations = try intValue(for: "--min-iterations")
    let maxIterations = try intValue(for: "--max-iterations")
    let fixedIterations = try intValue(for: "--iterations")
    if hasFlag("--adaptive") || minDuration != nil || maxDuration != nil || minIterations != nil
      || maxIterations != nil
    {
      return .adaptive(
        minIterations: minIterations ?? 1,
        maxIterations: maxIterations ?? fixedIterations ?? 100,
        minDurationNanoseconds: minDuration,
        maxDurationNanoseconds: maxDuration
      )
    }
    guard let count = fixedIterations else {
      return defaultPolicy
    }
    return .iterations(count)
  }

  func intValue(for key: String) throws -> Int? {
    guard let value = value(for: key) else {
      return nil
    }
    guard let integer = Int(value) else {
      throw BenchmarkHostError.invalidNumber(key, value)
    }
    return integer
  }

  func uint64Value(for key: String) throws -> UInt64? {
    guard let value = value(for: key) else {
      return nil
    }
    guard let integer = UInt64(value) else {
      throw BenchmarkHostError.invalidNumber(key, value)
    }
    return integer
  }

  func metricProviders() -> [any MetricProvider] {
    values(for: "--optional-diagnostic").map {
      UnavailableMetricProvider(metricName: $0, reason: "Diagnostic unavailable from host request")
    }
      + values(for: "--required-diagnostic").map {
        UnavailableMetricProvider(
          metricName: $0,
          reason: "Required diagnostic unavailable from host request",
          requirement: .required
        )
      }
  }

  func traceExporters(runID: ReportID) -> [any TraceExporter] {
    values(for: "--trace").map { traceExporter(path: $0, runID: runID, required: false) }
      + values(for: "--required-trace").map {
        traceExporter(path: $0, runID: runID, required: true)
      }
  }

  private func traceExporter(path: String, runID: ReportID, required: Bool) -> TraceArtifactExporter
  {
    TraceArtifactExporter(
      artifact: TraceArtifact(
        tracePath: path,
        command: value(for: "--trace-command").map { [$0] } ?? [],
        metadata: traceMetadata()
      ),
      requirement: required ? .required : .optional
    )
  }

  private func traceMetadata() -> [String: String] {
    var metadata: [String: String] = [:]
    if let tool = value(for: "--trace-tool") {
      metadata["tool"] = tool
    }
    if let template = value(for: "--trace-template") {
      metadata["template"] = template
    }
    return metadata
  }
}
