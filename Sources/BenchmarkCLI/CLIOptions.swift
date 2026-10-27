// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Report

struct CLIOptions {
  private static let flags: Set<String> = [
    "--adaptive",
    "--allocation-sites",
    "--allow-debug",
    "--fail-on-regression",
    "--quiet",
    "--timeline",
  ]
  /// Options that choose which steps run.
  private static let selectionOptions = ["--suite", "--case", "--tag"]
  /// Options that override each step's configuration in the host.
  private static let configurationOptions = [
    "--warmup", "--iterations", "--batch-size",
    "--min-iterations", "--max-iterations", "--min-duration-ns", "--max-duration-ns",
  ]
  private static let valueOptions =
    Set(selectionOptions + configurationOptions).union([
      "--host", "--interposer", "--swift-version", "--input", "--output", "--format",
      "--baseline",
      "--statistic", "--threshold", "--budget", "--case-budget",
      "--trace", "--required-trace", "--trace-tool", "--trace-template", "--trace-command",
      "--xctrace-output", "--xctrace-template", "--xcrun",
    ])

  private var values: [String: [String]] = [:]
  private var flags: Set<String> = []

  init(_ arguments: [String]) throws {
    var index = arguments.startIndex
    while index < arguments.endIndex {
      let key = arguments[index]
      guard Self.flags.contains(key) || Self.valueOptions.contains(key) else {
        throw CLIError.unexpectedArgument(key)
      }
      if Self.flags.contains(key) {
        flags.insert(key)
        index += 1
        continue
      }
      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex, !arguments[valueIndex].hasPrefix("--") else {
        throw CLIError.missingValue(key)
      }
      values[key, default: []].append(arguments[valueIndex])
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

  func requiredValue(for key: String) throws -> String {
    guard let value = value(for: key) else {
      throw CLIError.missingOption(key)
    }
    return value
  }

  /// The host named by `--host`, with the interposer named by `--interposer`.
  func host() throws -> HostProcess {
    HostProcess(path: try requiredValue(for: "--host"), interposerPath: value(for: "--interposer"))
  }

  /// The host arguments that select the requested steps.
  var selectionArguments: [String] {
    arguments(for: Self.selectionOptions)
  }

  /// The host arguments that override the configuration of measured steps.
  var configurationArguments: [String] {
    arguments(for: Self.configurationOptions) + (hasFlag("--adaptive") ? ["--adaptive"] : [])
  }

  func format(default defaultFormat: ReportFormat = .console) throws -> ReportFormat {
    guard let value = value(for: "--format") else {
      return defaultFormat
    }
    guard let format = ReportFormat(rawValue: value) else {
      throw CLIError.invalidFormat(value, allowed: ReportFormat.allCases.map(\.rawValue))
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

  /// Exporters that attach the traces named by `--trace` and
  /// `--required-trace` to every case.
  func traceExporters() -> [any TraceExporter] {
    var metadata: [String: String] = [:]
    metadata["tool"] = value(for: "--trace-tool")
    metadata["template"] = value(for: "--trace-template")
    let command = value(for: "--trace-command").map { [$0] } ?? []
    func exporter(_ path: String, _ requirement: DiagnosticRequirement) -> any TraceExporter {
      TraceArtifactExporter(
        artifact: TraceArtifact(tracePath: path, command: command, metadata: metadata),
        requirement: requirement
      )
    }
    return values(for: "--trace").map { exporter($0, .optional) }
      + values(for: "--required-trace").map { exporter($0, .required) }
  }

  func writeOrReturn(_ output: String) throws -> String {
    if let outputPath = value(for: "--output") {
      try output.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
    }
    return hasFlag("--quiet") ? "" : output
  }

  private func arguments(for keys: [String]) -> [String] {
    keys.flatMap { key in values(for: key).flatMap { [key, $0] } }
  }
}
