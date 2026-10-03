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
  public static func run(
    discoveries: [any _BenchmarkDiscovery.Type],
    arguments: [String] = Array(CommandLine.arguments.dropFirst()),
    metadata: RunMetadata = .local(id: "run:benchmark-host")
  ) async throws {
    let output = try await render(
      discoveries: discoveries, arguments: arguments, metadata: metadata)
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
      let baseline = try options.value(for: "--baseline").map(readBaseline)
      let output = try await BenchmarkCommand().run(
        plan: plan,
        metadata: metadata,
        baseline: baseline,
        baselineMetric: try options.metric(default: .mean),
        threshold: try options.threshold(default: .relativePercentage(10)),
        budgets: try options.budgets(),
        timelineCapture: command == "trace" || options.hasFlag("--timeline")
          ? .benchmarkIterations : .disabled,
        metricProviders: options.metricProviders(),
        traceExporters: options.traceExporters(runID: metadata.id),
        format: try options.format(default: .console)
      )
      let emitted = try writeOrReturn(output, options: options)
      if command == "check" {
        let document = try JSONDecoder().decode(
          ReportDocument.self,
          from: Data(
            try await BenchmarkCommand().run(
              plan: plan,
              metadata: metadata,
              baseline: baseline,
              baselineMetric: try options.metric(default: .mean),
              threshold: try options.threshold(default: .relativePercentage(10)),
              budgets: try options.budgets(),
              metricProviders: options.metricProviders(),
              traceExporters: options.traceExporters(runID: metadata.id),
              format: .json
            ).utf8)
        )
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
      run [--suite <name>] [--case <name>] [--tag <tag>] [--warmup <n>] [--iterations <n>] [--adaptive] [--min-duration-ns <n>] [--max-duration-ns <n>] [--format console|json|markdown|speedscope] [--baseline <path>] [--output <path>] [--trace <path>] [--required-trace <path>]
      check --baseline <path> [--suite <name>] [--case <name>] [--tag <tag>]
      trace [same options as run, with timeline capture enabled]
    """
  }

  private static func readBaseline(_ path: String) throws -> BaselineDocument {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(BaselineDocument.self, from: data)
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
  case invalidMetric(String)
  case invalidBudget(String)
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
    case .invalidMetric(let metric):
      return "Invalid metric '\(metric)'."
    case .invalidBudget(let budget):
      return "Invalid budget '\(budget)'."
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

  func metric(default defaultMetric: Report.Measurement.Metric) throws -> Report.Measurement.Metric
  {
    guard let value = value(for: "--baseline-metric") ?? value(for: "--metric") else {
      return defaultMetric
    }
    guard let metric = Report.Measurement.Metric(rawValue: value) else {
      throw BenchmarkHostError.invalidMetric(value)
    }
    return metric
  }

  func threshold(default defaultPolicy: ThresholdPolicy) throws -> ThresholdPolicy {
    if let value = value(for: "--threshold-ns") {
      guard let absolute = Double(value) else {
        throw BenchmarkHostError.invalidNumber("--threshold-ns", value)
      }
      return .absoluteNanoseconds(absolute)
    }
    if let value = value(for: "--threshold-percent") {
      guard let relative = Double(value) else {
        throw BenchmarkHostError.invalidNumber("--threshold-percent", value)
      }
      return .relativePercentage(relative)
    }
    return defaultPolicy
  }

  func configuration(overriding configuration: BenchmarkConfiguration) throws
    -> BenchmarkConfiguration
  {
    BenchmarkConfiguration(
      warmup: try warmup(default: configuration.warmup),
      iterations: try iterations(default: configuration.iterations)
    )
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

  func budgets() throws -> [BudgetPolicy] {
    try values(for: "--budget").map(parseBudget)
      + values(for: "--case-budget").map(parseCaseBudget)
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

  private func parseBudget(_ value: String) throws -> BudgetPolicy {
    let parts = value.split(separator: ":").map(String.init)
    guard parts.count == 2 else {
      throw BenchmarkHostError.invalidBudget(value)
    }
    return BudgetPolicy(
      metric: try parseMetric(parts[0]),
      limitNanoseconds: try parseDouble(parts[1], option: "--budget")
    )
  }

  private func parseCaseBudget(_ value: String) throws -> BudgetPolicy {
    let parts = value.split(separator: ":").map(String.init)
    guard parts.count == 4 else {
      throw BenchmarkHostError.invalidBudget(value)
    }
    return BudgetPolicy(
      suiteName: parts[0],
      caseName: parts[1],
      metric: try parseMetric(parts[2]),
      limitNanoseconds: try parseDouble(parts[3], option: "--case-budget")
    )
  }

  private func parseMetric(_ value: String) throws -> Report.Measurement.Metric {
    guard let metric = Report.Measurement.Metric(rawValue: value) else {
      throw BenchmarkHostError.invalidMetric(value)
    }
    return metric
  }

  private func parseDouble(_ value: String, option: String) throws -> Double {
    guard let double = Double(value) else {
      throw BenchmarkHostError.invalidNumber(option, value)
    }
    return double
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
