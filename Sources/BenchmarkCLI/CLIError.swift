// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

enum CLIExitCode: Int32 {
  case success = 0
  case invalidConfiguration = 2
  case executionFailure = 3
  case regressionFailure = 20
  /// A required trace was missing, or recording one failed.
  case traceUnavailable = 30
}

enum CLIError: Error, CustomStringConvertible {
  case unknownCommand(String)
  case unexpectedArgument(String)
  case missingValue(String)
  case missingOption(String)
  case invalidFormat(String, allowed: [String])
  case noBenchmarksSelected
  case hostFailure(status: Int32, stderr: String)
  /// The host rejected the request or its configuration.
  case hostRejected(stderr: String)
  case unreadableInput(path: String, reason: String)
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

  /// What the command printed before failing, shown on standard output.
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
    case .invalidFormat(let format, let allowed):
      return "Invalid format '\(format)'. Use \(allowed.joined(separator: ", "))."
    case .noBenchmarksSelected:
      return "No benchmarks matched the requested filters."
    case .hostFailure(let status, let stderr):
      let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return message.isEmpty
        ? "Benchmark host exited with status \(status)."
        : "Benchmark host exited with status \(status): \(message)"
    case .hostRejected(let stderr):
      return "Benchmark host rejected the request: "
        + stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    case .unreadableInput(let path, let reason):
      return "Cannot read report '\(path)': \(reason)"
    case .regressionFailure:
      return "Regression check failed."
    }
  }
}
