// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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
    } catch let error as ComparisonArgumentError {
      fail(error.description, .invalidConfiguration)
    } catch let error as CheckGateError {
      fail(error.description, .invalidConfiguration)
    } catch let error as BaselineReadError {
      fail(error.description, .invalidConfiguration)
    } catch let error as BenchmarkCommandError {
      fail(error.description, .requiredDiagnosticUnavailable)
    } catch let error as XctraceRecorderError {
      fail(error.description, .requiredDiagnosticUnavailable)
    } catch {
      fail("\(error)", .executionFailure)
    }
  }

  static func run(_ arguments: [String]) async throws -> String {
    guard let command = arguments.first else {
      return help()
    }
    let tail = Array(arguments.dropFirst())

    switch command {
    case "--version":
      return "swift-benchmark-cli \(CLIVersion.current)"
    case "help", "--help", "-h":
      return help()
    case "list":
      return try HostCommands.list(tail)
    case "run", "check", "trace":
      return try await HostCommands.measure(command, tail)
    case "render":
      return try ReportCommands.render(tail)
    case "compare", "diff":
      return try ReportCommands.compare(tail, failOnRegression: false)
    case "baseline":
      return try ReportCommands.baseline(tail)
    default:
      throw CLIError.unknownCommand(command)
    }
  }

  static func help() -> String {
    """
    swift-benchmark-cli

    Commands:
      list --host <path> [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json]
      run --host <path> [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json|speedscope] [--output <path>]
      check --host <path> [--baseline <baseline.json>] [--allow-debug] [--suite <name>] [--case <name>] [--tag <tag>]
      trace --host <path> [same options as run] [--xctrace-output <path>]
      render --input <report.json> [--format console|json|speedscope] [--output <path>]
      compare|diff --input <report.json> --baseline <baseline.json> [--statistic <name>] [--threshold [<metric>=]<value>] [--fail-on-regression]
      baseline write --input <report.json> --output <baseline.json>
      baseline update --input <report.json> --output <baseline.json>
      baseline check --input <report.json> --baseline <baseline.json> [--statistic <name>] [--threshold [<metric>=]<value>]
      help

    Each step of run and check is measured in a process of its own; trace with
    --xctrace-output records every selected step in one process.

    Options:
      --version
      --host <path>
      --swift-version <text>   (the compiler that built the host, for run metadata)
      --statistic min|max|mean|median|standardDeviation|p90|p95|p99   (default median)
      --threshold <n>% | <metric>=<n>%|<amount>   (default 10%)
      --budget <metric>:<statistic>:<amount>
      --case-budget <suite>:<case>:<metric>:<statistic>:<amount>
      --allow-debug   (let check judge a debug build)
      --tag <tag>
      --warmup <n>
      --iterations <n>
      --batch-size <n>   (default: automatic batching)
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
      --trace-tool <name>
      --trace-template <name>
      --trace-command <command>
      --xctrace-output <path>
      --xctrace-template <name>
      --xcrun <path>
      --quiet
    """
  }

  private static func fail(_ message: String, _ code: CLIExitCode) -> Never {
    fputs("swift-benchmark-cli: \(message)\n", stderr)
    Foundation.exit(code.rawValue)
  }
}
