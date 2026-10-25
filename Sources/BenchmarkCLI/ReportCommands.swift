// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Report

/// `render`, `compare` and `baseline`, which work on saved JSON reports.
enum ReportCommands {
  static func render(_ arguments: [String]) throws -> String {
    let options = try CLIOptions(arguments)
    let document = try readReport(options.requiredValue(for: "--input"))
    return try options.writeOrReturn(try options.format().render(document))
  }

  static func compare(_ arguments: [String], failOnRegression: Bool) throws -> String {
    let options = try CLIOptions(arguments)
    let document = try readReport(options.requiredValue(for: "--input")).comparing(
      baseline: BaselineDocument.read(path: options.requiredValue(for: "--baseline")),
      comparison: try options.comparison()
    )
    let emitted = try options.writeOrReturn(try options.format().render(document))
    if failOnRegression || options.hasFlag("--fail-on-regression") {
      try CheckGate.validate(
        buildConfiguration: document.metadata.buildConfiguration,
        allowDebug: options.hasFlag("--allow-debug"))
      guard document.summary.failedRegressionCount == 0 && document.summary.failedBudgetCount == 0
      else {
        throw CLIError.regressionFailure(output: emitted)
      }
    }
    return emitted
  }

  static func baseline(_ arguments: [String]) throws -> String {
    guard let subcommand = arguments.first else {
      throw CLIError.missingOption("baseline subcommand")
    }
    let tail = Array(arguments.dropFirst())
    switch subcommand {
    case "write", "update":
      let options = try CLIOptions(tail)
      let output = try options.requiredValue(for: "--output")
      let baseline = BaselineDocument(
        document: try readReport(options.requiredValue(for: "--input")))
      try JSONOutput.encode(baseline).write(
        to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
      return options.hasFlag("--quiet") ? "" : "Wrote baseline \(output)"
    case "check":
      return try compare(tail, failOnRegression: true)
    default:
      throw CLIError.unknownCommand("baseline \(subcommand)")
    }
  }

  private static func readReport(_ path: String) throws -> ReportDocument {
    do {
      return try JSONDecoder().decode(
        ReportDocument.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
      throw CLIError.unreadableInput(path: path, reason: error.localizedDescription)
    }
  }
}

enum JSONOutput {
  static func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}
