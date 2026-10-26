// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report

/// A benchmark host executable.
///
/// Every invocation writes its JSON to a file the CLI names, so whatever the
/// benchmarks print cannot corrupt it; the host's standard output is passed
/// through to the CLI's standard error.
struct HostProcess {
  var path: String
  /// The interposer library that counting processes load before any other.
  var interposerPath: String?

  /// The steps the host would measure for `selection`.
  func plan(_ selection: [String]) throws -> HostPlan {
    try invoke(["list"] + selection)
  }

  func measure(_ arguments: [String]) throws -> HostMeasurement {
    try invoke(["measure"] + arguments)
  }

  /// Measures one step: in one process, or, given the interposer, timed in
  /// one process and counted in another that loads the interposer and calls
  /// the step in batches of the timed size. `countingArguments` go only to
  /// the process that counts.
  func measureStep(
    _ stepID: String, _ arguments: [String], countingArguments: [String] = []
  ) throws -> HostMeasurement {
    let step = ["--step", stepID, "--isolated"]
    guard let interposerPath else {
      return try measure(step + arguments + countingArguments)
    }
    var timing = try measure(step + arguments + ["--timing-only"])
    guard let batchSize = timing.timedBatchSize(ofStep: stepID) else {
      return timing
    }
    let counting: HostMeasurement = try invoke(
      ["measure"] + step + arguments.filter { $0 != "--timeline" } + countingArguments
        + ["--counting-only", "--batch-size", String(batchSize)],
      injecting: interposerPath
    )
    // A library that loads without the interposer's functions counts
    // nothing, which would leave heap budgets and comparisons unjudged.
    guard
      counting.records.contains(where: {
        $0.kind == .sampleRecorded
          && $0.context.values[Benchmark.Metric.heapAllocations.name] != nil
      })
    else {
      throw CLIError.interposerCountedNothing(path: interposerPath)
    }
    timing.insertCountingSamples(ofStep: stepID, from: counting)
    return timing
  }

  /// A fresh path for a host to write its output to.
  static func temporaryOutputURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-host-\(UUID().uuidString).json")
  }

  static func decode<Output: Decodable>(_ type: Output.Type, at url: URL) throws -> Output {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  private func invoke<Output: Decodable>(
    _ arguments: [String], injecting library: String? = nil
  ) throws -> Output {
    let outputURL = Self.temporaryOutputURL()
    defer { try? FileManager.default.removeItem(at: outputURL) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments + ["--output", outputURL.path]
    if let library {
      #if canImport(Darwin)
        let variable = "DYLD_INSERT_LIBRARIES"
      #else
        let variable = "LD_PRELOAD"
      #endif
      var environment = ProcessInfo.processInfo.environment
      environment[variable] = [library, environment[variable]].compactMap { $0 }
        .joined(separator: ":")
      process.environment = environment
    }
    process.standardOutput = FileHandle.standardError
    let capture = try ProcessOutputCapture()
    process.standardError = capture.error
    try process.run()
    process.waitUntilExit()

    let errorOutput = capture.standardError()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      if process.terminationReason == .exit, process.terminationStatus == 2 {
        throw CLIError.hostRejected(stderr: errorOutput)
      }
      throw CLIError.hostFailure(status: process.terminationStatus, stderr: errorOutput)
    }
    FileHandle.standardError.write(Data(errorOutput.utf8))
    return try Self.decode(Output.self, at: outputURL)
  }
}
