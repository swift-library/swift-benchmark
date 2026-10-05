// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Dispatch
import Foundation
import Report

@main
struct BenchmarkCLI {
  static func main() async {
    do {
      let output = try await run(Array(CommandLine.arguments.dropFirst()))
      if !output.isEmpty {
        print(output)
      }
    } catch let error as CLIError {
      if let output = error.output, !output.isEmpty {
        print(output)
      }
      if !error.description.isEmpty {
        fputs("swift-benchmark-cli: \(error.description)\n", stderr)
      }
      Foundation.exit(error.exitCode.rawValue)
    } catch let error as BenchmarkCommandError {
      fputs("swift-benchmark-cli: \(error.description)\n", stderr)
      Foundation.exit(CLIExitCode.requiredDiagnosticUnavailable.rawValue)
    } catch let error as XctraceRecorderError {
      fputs("swift-benchmark-cli: \(error.description)\n", stderr)
      Foundation.exit(CLIExitCode.requiredDiagnosticUnavailable.rawValue)
    } catch let error as BenchmarkRunnerError {
      fputs("swift-benchmark-cli: \(error.description)\n", stderr)
      Foundation.exit(CLIExitCode.executionFailure.rawValue)
    } catch {
      fputs("swift-benchmark-cli: \(error)\n", stderr)
      Foundation.exit(CLIExitCode.executionFailure.rawValue)
    }
  }

  static func run(_ arguments: [String]) async throws -> String {
    guard let command = arguments.first else {
      return help()
    }

    switch command {
    case "--version":
      return "swift-benchmark-cli \(CLIVersion.current)"
    case "help", "--help", "-h":
      return help()
    case "list":
      return try await runHostCommand("list", Array(arguments.dropFirst()))
    case "run", "sample":
      return try await runHostCommand("run", Array(arguments.dropFirst()))
    case "check":
      return try await runHostCommand("check", Array(arguments.dropFirst()))
    case "trace":
      return try await runHostCommand("trace", Array(arguments.dropFirst()))
    case "render":
      return try render(Array(arguments.dropFirst()))
    case "compare":
      return try compare(Array(arguments.dropFirst()), failOnRegression: false)
    case "diff":
      return try compare(Array(arguments.dropFirst()), failOnRegression: false)
    case "baseline":
      return try await baseline(Array(arguments.dropFirst()))
    default:
      throw CLIError.unknownCommand(command)
    }
  }

  static func help() -> String {
    """
    swift-benchmark-cli

    Commands:
      list --host <path> [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json]
      run --host <path> [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json|markdown|speedscope] [--output <path>]
      check --host <path> --baseline <baseline.json> [--suite <name>] [--case <name>] [--tag <tag>]
      trace --host <path> [same options as run]
      render --input <report.json> [--format console|json|markdown|speedscope] [--output <path>]
      compare|diff --input <report.json> --baseline <baseline.json> [--baseline-metric mean|median|p90|p95|p99] [--threshold-percent <n>|--threshold-ns <n>] [--fail-on-regression]
      baseline write --input <report.json> --output <baseline.json>
      baseline update --input <report.json> --output <baseline.json>
      baseline check --input <report.json> --baseline <baseline.json> [--baseline-metric mean|median|p90|p95|p99]
      help

    Options:
      --version
      --host <path>
      --budget <metric>:<nanoseconds>
      --case-budget <suite>:<case>:<metric>:<nanoseconds>
      --tag <tag>
      --warmup <n>
      --iterations <n>
      --adaptive
      --min-iterations <n>
      --max-iterations <n>
      --min-duration-ns <n>
      --max-duration-ns <n>
      --timeline
      --optional-diagnostic <name>
      --required-diagnostic <name>
      --trace <path>
      --required-trace <path>
      --xctrace-output <path>
      --xctrace-template <name>
      --xcrun <path>
      --quiet
    """
  }

  private static func runHostCommand(_ command: String, _ arguments: [String]) async throws
    -> String
  {
    let options = try CLIOptions(arguments)
    let host = try options.requiredValue(for: "--host")
    let hostExclusions: Set<String> = [
      "--host", "--xctrace-output", "--xctrace-template", "--xcrun",
    ]
    guard let xctraceOutput = options.value(for: "--xctrace-output") else {
      let hostArguments = [command] + options.forwardedArguments(excluding: hostExclusions)
      return try invokeHost(path: host, arguments: hostArguments)
    }
    guard command != "list" else {
      throw CLIError.unexpectedArgument("--xctrace-output")
    }
    return try await runTracedHostCommand(
      command, options: options, host: host, xctraceOutput: xctraceOutput,
      hostExclusions: hostExclusions)
  }

  // xctrace turns every nonzero host exit into its own failure status, so the traced host
  // always emits JSON and the CLI applies the requested format, output, and check gate.
  private static func runTracedHostCommand(
    _ command: String,
    options: CLIOptions,
    host: String,
    xctraceOutput: String,
    hostExclusions: Set<String>
  ) async throws -> String {
    let reportURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-host-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: reportURL) }
    let hostArguments =
      [command == "check" ? "run" : command]
      + options.forwardedArguments(
        excluding: hostExclusions.union(["--format", "--output", "--quiet"]))
      + ["--format", "json"]
    let artifact = try await XctraceRecorder(
      xcrunPath: options.value(for: "--xcrun") ?? "/usr/bin/xcrun"
    ).record(
      executablePath: host,
      executableArguments: hostArguments,
      outputTracePath: xctraceOutput,
      template: options.value(for: "--xctrace-template") ?? "Time Profiler",
      targetStandardOutputPath: reportURL.path
    )

    var document = try readReport(reportURL.path)
    let exporter = TraceArtifactExporter(artifact: artifact)
    for suiteIndex in document.suites.indices {
      for caseIndex in document.suites[suiteIndex].cases.indices {
        let scope = document.suites[suiteIndex].cases[caseIndex].scope
        document.suites[suiteIndex].cases[caseIndex].attachments +=
          await exporter.attachments(for: scope)
      }
    }

    let output = try options.format(default: .console).render(document)
    let emitted = try writeOrReturn(output, options: options)
    if command == "check" {
      guard document.summary.failedRegressionCount == 0 && document.summary.failedBudgetCount == 0
      else {
        throw CLIError.regressionFailure(output: emitted)
      }
    }
    return emitted
  }

  private static func render(_ arguments: [String]) throws -> String {
    let options = try CLIOptions(arguments)
    let input = try options.requiredValue(for: "--input")
    let format = try options.format()
    let document = try readReport(input)
    let output = try format.render(document)
    return try writeOrReturn(output, options: options)
  }

  private static func compare(_ arguments: [String], failOnRegression: Bool) throws -> String {
    let options = try CLIOptions(arguments)
    let input = try options.requiredValue(for: "--input")
    let baselinePath = try options.requiredValue(for: "--baseline")
    let document = try readReport(input).comparing(
      baseline: readBaseline(baselinePath),
      baselineMetric: try options.metric(default: .mean),
      threshold: try options.threshold(default: .relativePercentage(10)),
      budgets: try options.budgets()
    )
    let output = try options.format(default: .console).render(document)
    let emitted = try writeOrReturn(output, options: options)
    if failOnRegression || options.hasFlag("--fail-on-regression") {
      guard document.summary.failedRegressionCount == 0 && document.summary.failedBudgetCount == 0
      else {
        throw CLIError.regressionFailure(output: emitted)
      }
    }
    return emitted
  }

  private static func baseline(_ arguments: [String]) async throws -> String {
    guard let subcommand = arguments.first else {
      throw CLIError.missingOption("baseline subcommand")
    }
    let tail = Array(arguments.dropFirst())
    switch subcommand {
    case "write", "update":
      let options = try CLIOptions(tail)
      let input = try options.requiredValue(for: "--input")
      let output = try options.requiredValue(for: "--output")
      try writeBaseline(BaselineDocument(document: readReport(input)), to: output)
      return options.hasFlag("--quiet") ? "" : "Wrote baseline \(output)"
    case "check":
      return try compare(tail, failOnRegression: true)
    default:
      throw CLIError.unknownCommand("baseline \(subcommand)")
    }
  }

  private static func readReport(_ path: String) throws -> ReportDocument {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(ReportDocument.self, from: data)
  }

  private static func decodeReport(_ json: String) throws -> ReportDocument {
    try JSONDecoder().decode(ReportDocument.self, from: Data(json.utf8))
  }

  private static func readBaseline(_ path: String) throws -> BaselineDocument {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(BaselineDocument.self, from: data)
  }

  private static func writeBaseline(_ baseline: BaselineDocument, to path: String) throws {
    try encodeJSON(baseline).write(
      to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
  }

  private static func invokeHost(path: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let stdoutCapture = PipeCapture()
    let stderrCapture = PipeCapture()
    stdoutCapture.startReading(stdout.fileHandleForReading)
    stderrCapture.startReading(stderr.fileHandleForReading)
    process.waitUntilExit()

    let output = stdoutCapture.string()
    let errorOutput = stderrCapture.string()
    if process.terminationReason == .exit,
      process.terminationStatus == BenchmarkHost.regressionFailureExitStatus
    {
      throw CLIError.regressionFailure(output: output.trimmingCharacters(in: .newlines))
    }
    guard process.terminationStatus == 0 else {
      throw CLIError.hostFailure(status: process.terminationStatus, stderr: errorOutput)
    }
    return output.trimmingCharacters(in: .newlines)
  }

  private static func writeOrReturn(_ output: String, options: CLIOptions) throws -> String {
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

private final class PipeCapture: @unchecked Sendable {
  private let group = DispatchGroup()
  private let lock = NSLock()
  private var data = Data()

  func startReading(_ fileHandle: FileHandle) {
    group.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      let captured = fileHandle.readDataToEndOfFile()
      lock.lock()
      data.append(captured)
      lock.unlock()
      group.leave()
    }
  }

  func string() -> String {
    group.wait()
    lock.lock()
    let captured = data
    lock.unlock()
    return String(decoding: captured, as: UTF8.self)
  }
}

struct CLIOptions {
  private static let flags: Set<String> = [
    "--adaptive",
    "--fail-on-regression",
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
        throw CLIError.unexpectedArgument(key)
      }
      if Self.flags.contains(key) {
        flags.insert(key)
        index += 1
        continue
      }
      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex else {
        throw CLIError.missingValue(key)
      }
      let value = arguments[valueIndex]
      guard !value.hasPrefix("--") else {
        throw CLIError.missingValue(key)
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

  func forwardedArguments(excluding excludedKeys: Set<String>) -> [String] {
    var arguments: [String] = []
    for flag in flags.sorted() where !excludedKeys.contains(flag) {
      arguments.append(flag)
    }
    for key in values.keys.sorted() where !excludedKeys.contains(key) {
      for value in values[key] ?? [] {
        arguments.append(key)
        arguments.append(value)
      }
    }
    return arguments
  }

  func requiredValue(for key: String) throws -> String {
    guard let value = value(for: key) else {
      throw CLIError.missingOption(key)
    }
    return value
  }

  func format(default defaultFormat: ReportFormat = .console) throws -> ReportFormat {
    guard let value = values["--format"]?.last else {
      return defaultFormat
    }
    guard let format = ReportFormat(rawValue: value) else {
      throw CLIError.invalidFormat(value)
    }
    return format
  }

  func intValue(for key: String, default defaultValue: Int) throws -> Int {
    guard let value = value(for: key) else {
      return defaultValue
    }
    guard let int = Int(value) else {
      throw CLIError.invalidInteger(key, value)
    }
    return int
  }

  func doubleValue(for key: String) throws -> Double? {
    guard let value = value(for: key) else {
      return nil
    }
    guard let double = Double(value) else {
      throw CLIError.invalidNumber(key, value)
    }
    return double
  }

  func warmup(default defaultValue: Int) throws -> WarmupPolicy {
    let count = try intValue(for: "--warmup", default: defaultValue)
    return count == 0 ? .none : .iterations(count)
  }

  func metric(default defaultMetric: Report.Measurement.Metric) throws -> Report.Measurement.Metric
  {
    guard let value = value(for: "--baseline-metric") ?? value(for: "--metric") else {
      return defaultMetric
    }
    guard let metric = Report.Measurement.Metric(rawValue: value) else {
      throw CLIError.invalidMetric(value)
    }
    return metric
  }

  func threshold(default defaultPolicy: ThresholdPolicy) throws -> ThresholdPolicy {
    if let absolute = try doubleValue(for: "--threshold-ns") {
      return .absoluteNanoseconds(absolute)
    }
    if let relative = try doubleValue(for: "--threshold-percent") {
      return .relativePercentage(relative)
    }
    return defaultPolicy
  }

  func budgets() throws -> [BudgetPolicy] {
    try values(for: "--budget").map(parseBudget)
      + values(for: "--case-budget").map(parseCaseBudget)
  }

  func metricProviders() -> [any MetricProvider] {
    values(for: "--optional-diagnostic").map {
      UnavailableMetricProvider(metricName: $0, reason: "Diagnostic unavailable from CLI request")
    }
      + values(for: "--required-diagnostic").map {
        UnavailableMetricProvider(
          metricName: $0,
          reason: "Required diagnostic unavailable from CLI request",
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
      throw CLIError.invalidBudget(value)
    }
    return BudgetPolicy(
      metric: try parseMetric(parts[0]),
      limitNanoseconds: try parseDouble(parts[1], option: "--budget")
    )
  }

  private func parseCaseBudget(_ value: String) throws -> BudgetPolicy {
    let parts = value.split(separator: ":").map(String.init)
    guard parts.count == 4 else {
      throw CLIError.invalidBudget(value)
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
      throw CLIError.invalidMetric(value)
    }
    return metric
  }

  private func parseDouble(_ value: String, option: String) throws -> Double {
    guard let double = Double(value) else {
      throw CLIError.invalidNumber(option, value)
    }
    return double
  }

  private func traceExporter(path: String, runID: ReportID, required: Bool) -> StaticTraceExporter {
    StaticTraceExporter(
      attachment: DiagnosticAttachment(
        id: ReportID(rawValue: "attachment:trace:\(stable(path))"),
        scope: ReportScope(runID: runID),
        kind: .trace,
        title: "Instruments trace",
        location: path,
        contentType: "application/vnd.apple.instruments.trace"
      ),
      requirement: required ? .required : .optional
    )
  }

  private func stable(_ value: String) -> String {
    let stableValue =
      value
      .lowercased()
      .map { character in
        character.isLetter || character.isNumber ? character : "-"
      }
      .reduce(into: "") { partial, character in
        if character == "-", partial.last == "-" {
          return
        }
        partial.append(character)
      }
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return stableValue.isEmpty ? "trace" : stableValue
  }
}

enum CLIExitCode: Int32 {
  case success = 0
  case invalidConfiguration = 2
  case executionFailure = 3
  case regressionFailure = 20
  case requiredDiagnosticUnavailable = 30
}

enum CLIError: Error, CustomStringConvertible {
  case unknownCommand(String)
  case unexpectedArgument(String)
  case missingValue(String)
  case missingOption(String)
  case invalidFormat(String)
  case invalidInteger(String, String)
  case invalidNumber(String, String)
  case invalidMetric(String)
  case invalidBudget(String)
  case noBenchmarksSelected
  case hostFailure(status: Int32, stderr: String)
  case regressionFailure(output: String)

  var exitCode: CLIExitCode {
    switch self {
    case .hostFailure:
      return .executionFailure
    case .regressionFailure:
      return .regressionFailure
    default:
      return .invalidConfiguration
    }
  }

  var output: String? {
    switch self {
    case .regressionFailure(let output):
      return output
    default:
      return nil
    }
  }

  var description: String {
    switch self {
    case .unknownCommand(let command):
      return "Unknown command '\(command)'."
    case .unexpectedArgument(let argument):
      return "Unexpected argument '\(argument)'."
    case .missingValue(let option):
      return "Missing value for \(option)."
    case .missingOption(let option):
      return "Missing required option \(option)."
    case .invalidFormat(let format):
      return "Invalid format '\(format)'. Use console, json, markdown, or speedscope."
    case .invalidInteger(let option, let value):
      return "Invalid integer '\(value)' for \(option)."
    case .invalidNumber(let option, let value):
      return "Invalid number '\(value)' for \(option)."
    case .invalidMetric(let metric):
      return "Invalid metric '\(metric)'."
    case .invalidBudget(let budget):
      return "Invalid budget '\(budget)'. Use metric:nanoseconds or suite:case:metric:nanoseconds."
    case .noBenchmarksSelected:
      return "No benchmarks matched the requested filters."
    case .hostFailure(let status, let stderr):
      let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return message.isEmpty
        ? "Benchmark host exited with status \(status)."
        : "Benchmark host exited with status \(status): \(message)"
    case .regressionFailure:
      return "Regression check failed."
    }
  }
}
