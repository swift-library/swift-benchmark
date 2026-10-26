// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Dispatch
import Foundation

/// Runs `executable` to completion and returns its standard output when
/// captured. Uncaptured streams pass through to the plugin's own.
@discardableResult
func runProcess(
  executable: URL,
  arguments: [String],
  captureOutput: Bool = false,
  captureOutputOnFailure: Bool = false
) throws -> String {
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  let capturesOutput = captureOutput || captureOutputOnFailure
  let stdout = Pipe()
  let stderr = Pipe()
  if capturesOutput {
    process.standardOutput = stdout
  }
  if captureOutputOnFailure {
    process.standardError = stderr
  }
  try process.run()

  let outputData = CapturedProcessData()
  let errorData = CapturedProcessData()
  let readers = DispatchGroup()
  func drain(_ pipe: Pipe, into captured: CapturedProcessData) {
    let handle = pipe.fileHandleForReading
    readers.enter()
    DispatchQueue.global().async {
      captured.data = handle.readDataToEndOfFile()
      readers.leave()
    }
  }
  if capturesOutput {
    drain(stdout, into: outputData)
  }
  if captureOutputOnFailure {
    drain(stderr, into: errorData)
  }
  process.waitUntilExit()
  readers.wait()

  let output = String(decoding: outputData.data, as: UTF8.self)
  guard process.terminationStatus == 0 else {
    throw PluginError.failed(
      executable: executable.lastPathComponent,
      status: process.terminationStatus,
      output: output,
      errorOutput: String(decoding: errorData.data, as: UTF8.self)
    )
  }
  return output
}

/// Data a reader thread fills before `DispatchGroup.wait()` returns.
private final class CapturedProcessData: @unchecked Sendable {
  var data = Data()
}

enum PluginError: Error, CustomStringConvertible {
  case buildFailed(String)
  case failed(executable: String, status: Int32, output: String, errorOutput: String)
  case noBenchmarksDiscovered
  case noObjectFiles(String)
  case swiftTestingRuntimeUnavailable([String])
  case unsupportedBinaryTarget(String, architecture: String)

  var description: String {
    switch self {
    case .buildFailed(let log):
      return "Package build failed while preparing benchmark host.\n\(log)"
    case .failed(let executable, let status, let output, let errorOutput):
      let details = [output, errorOutput]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      return details.isEmpty
        ? "\(executable) exited with status \(status)."
        : "\(executable) exited with status \(status):\n\(details)"
    case .noBenchmarksDiscovered:
      return
        "No @BenchmarkSuite declarations were discovered in library targets and no @Suite(.benchmark...) or @Test(.benchmark...) declarations were discovered in test targets."
    case .noObjectFiles(let directory):
      return "No Swift object files were found under \(directory)."
    case .unsupportedBinaryTarget(let path, let architecture):
      return "\(path) has no macOS library for \(architecture) to link into the benchmark host."
    case .swiftTestingRuntimeUnavailable(let attempted):
      return """
        Swift Testing runtime was required for BenchmarkTesting bridge compilation, but no supported runtime layout was found.
        Attempted:
        \(attempted.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
  }
}
