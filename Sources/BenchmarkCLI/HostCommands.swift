// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Report

/// `list`, `run`, `check` and `trace`, which drive a benchmark host.
enum HostCommands {
  static func list(_ arguments: [String]) throws -> String {
    let options = try CLIOptions(arguments)
    let host = try options.host()
    let format = try options.format()
    guard format == .console || format == .json else {
      throw CLIError.invalidFormat(format.rawValue, allowed: ["console", "json"])
    }
    let steps = try host.plan(options.selectionArguments).steps
    if format == .json {
      return try options.writeOrReturn(JSONOutput.encode(steps))
    }
    return try options.writeOrReturn(steps.map(consoleLine).joined(separator: "\n"))
  }

  /// Measures the selected steps and reports them. Each step runs in a host
  /// process of its own, which isolates its memory and runtime state and
  /// lets the step record peak memory, and with `--interposer` in a second
  /// process that counts its allocations; with `--xctrace-output`, one
  /// traced process measures every step instead.
  static func measure(_ command: String, _ arguments: [String]) async throws -> String {
    let options = try CLIOptions(arguments)
    let host = try options.host()
    let format = try options.format()
    let comparison = try options.comparison()
    let baseline = try options.value(for: "--baseline").map(BaselineDocument.read(path:))
    let plan = try host.plan(options.selectionArguments)
    if command == "check" {
      try CheckGate.validate(
        buildConfiguration: plan.metadata.buildConfiguration,
        allowDebug: options.hasFlag("--allow-debug"))
    }

    let timeline = command == "trace" || options.hasFlag("--timeline") ? ["--timeline"] : []
    var traceExporters = options.traceExporters()
    var measurements: [HostMeasurement]
    if let traceOutput = options.value(for: "--xctrace-output") {
      let traced = try await recordTrace(
        host: host,
        arguments: options.selectionArguments + options.configurationArguments + timeline,
        outputPath: traceOutput,
        options: options
      )
      measurements = [traced.measurement]
      traceExporters.append(TraceArtifactExporter(artifact: traced.artifact))
    } else {
      measurements = try plan.steps.map { step in
        try host.measureStep(step.id, options.configurationArguments + timeline)
      }
    }
    if let swiftVersion = options.value(for: "--swift-version") {
      for index in measurements.indices {
        measurements[index].metadata.swiftVersion = swiftVersion
      }
    }

    guard
      let document = try await BenchmarkCommand.document(
        measurements: measurements,
        baseline: baseline,
        comparison: comparison,
        traceExporters: traceExporters
      )
    else {
      throw CLIError.noBenchmarksSelected
    }
    let emitted = try options.writeOrReturn(try format.render(document))
    if command == "check",
      document.summary.failedRegressionCount > 0 || document.summary.failedBudgetCount > 0
    {
      throw CLIError.regressionFailure(output: emitted)
    }
    return emitted
  }

  private static func recordTrace(
    host: HostProcess,
    arguments: [String],
    outputPath: String,
    options: CLIOptions
  ) async throws -> (measurement: HostMeasurement, artifact: TraceArtifact) {
    let measurementURL = HostProcess.temporaryOutputURL()
    defer { try? FileManager.default.removeItem(at: measurementURL) }
    let artifact = try await XctraceRecorder(
      xcrunPath: options.value(for: "--xcrun") ?? "/usr/bin/xcrun"
    ).record(
      executablePath: host.path,
      executableArguments: ["measure"] + arguments + ["--output", measurementURL.path],
      outputTracePath: outputPath,
      template: options.value(for: "--xctrace-template") ?? "Time Profiler"
    )
    return (try HostProcess.decode(HostMeasurement.self, at: measurementURL), artifact)
  }

  private static func consoleLine(_ entry: BenchmarkListEntry) -> String {
    let tags = entry.tags.isEmpty ? "" : " tags=\(entry.tags.joined(separator: ","))"
    let arguments =
      entry.arguments.isEmpty
      ? "" : " arguments=\(entry.arguments.map(\.label).joined(separator: ","))"
    let size = entry.dimensionSizes.first.map { " size=\($0)" } ?? ""
    return "\(entry.suite).\(entry.caseName)\(tags)\(arguments)\(size)"
  }
}
