// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Report

/// A benchmark host executable.
///
/// Every invocation writes its JSON to a file the CLI names, so whatever the
/// benchmarks print cannot corrupt it; the host's standard output is passed
/// through to the CLI's standard error.
struct HostProcess {
  var path: String

  /// The steps the host would measure for `selection`.
  func plan(_ selection: [String]) throws -> HostPlan {
    try invoke(["list"] + selection)
  }

  func measure(_ arguments: [String]) throws -> HostMeasurement {
    try invoke(["measure"] + arguments)
  }

  /// A fresh path for a host to write its output to.
  static func temporaryOutputURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-host-\(UUID().uuidString).json")
  }

  static func decode<Output: Decodable>(_ type: Output.Type, at url: URL) throws -> Output {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  private func invoke<Output: Decodable>(_ arguments: [String]) throws -> Output {
    let outputURL = Self.temporaryOutputURL()
    defer { try? FileManager.default.removeItem(at: outputURL) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments + ["--output", outputURL.path]
    process.standardOutput = FileHandle.standardError
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    let errorCapture = PipeCapture()
    errorCapture.startReading(errorPipe.fileHandleForReading)
    process.waitUntilExit()

    let errorOutput = errorCapture.string()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw CLIError.hostFailure(status: process.terminationStatus, stderr: errorOutput)
    }
    FileHandle.standardError.write(Data(errorOutput.utf8))
    return try Self.decode(Output.self, at: outputURL)
  }
}
