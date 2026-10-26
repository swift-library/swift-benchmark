// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

// Fixture deadlines include cold dependency builds on hosted runners.
@Suite("CLI Workflow")
struct CLIWorkflowTests {
  @Test(.timeLimit(.minutes(1)))
  func subprocessCaptureHandlesLargeOutputAndFailures() async throws {
    let script =
      "BEGIN { for (i = 0; i < 131072; i++) { printf \"o\"; printf \"e\" > \"/dev/stderr\" } }"
    let output = try await runProcess(executable: "/usr/bin/awk", arguments: [script])
    #expect(output == String(repeating: "o", count: 131072))

    let failure = try await runProcessFailure(
      executable: "/usr/bin/awk", arguments: [script + " END { exit 7 }"])
    #expect(
      failure == String(repeating: "o", count: 131072) + "\n"
        + String(repeating: "e", count: 131072))
  }

  @Test(.timeLimit(.minutes(3)))
  func cliProductsReportTheSameVersion() async throws {
    let version = try await runProcess(executable: cliPath(), arguments: ["--version"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let aliasVersion = try await runProcess(
      executable: URL(fileURLWithPath: try cliPath()).deletingLastPathComponent()
        .appendingPathComponent("BenchmarkCLI").path,
      arguments: ["--version"]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(version.hasPrefix("swift-benchmark-cli "))
    #expect(version == aliasVersion)
  }

  @Test(.timeLimit(.minutes(3)))
  func cliReportsHelpAndInvalidCommands() async throws {
    let help = try await runProcess(executable: cliPath(), arguments: ["--help"])
    let invalidCommand = try await processResult(
      executable: cliPath(), arguments: ["invalid-command"])
    let missingInput = try await processResult(
      executable: cliPath(), arguments: ["render", "--input", "/nonexistent/report.json"])

    #expect(help.contains("Commands:"))
    #expect(invalidCommand.status == 2)
    #expect(missingInput.status == 2)
  }

  @Test(.timeLimit(.minutes(3)))
  func runMeasuresEachStepInAHostProcessOfItsOwn() async throws {
    let fake = try await FakeHost(buildConfiguration: "release")
    defer { fake.remove() }

    let run = try await runProcess(
      executable: try cliPath(),
      arguments: ["run", "--host", fake.host.path, "--iterations", "3", "--format", "json"]
    )
    let launches = try fake.launches()

    #expect(launches.map { $0.split(separator: " ").first } == ["list", "measure", "measure"])
    #expect(launches.dropFirst().allSatisfy { $0.contains("--isolated --iterations 3") })
    #expect(Set(launches.dropFirst().map { $0.split(separator: " ")[2] }).count == 2)
    #expect(run.contains("\"name\" : \"First\""))
  }

  @Test(.timeLimit(.minutes(3)))
  func tracedCommandsMeasureEveryStepInOneHostProcess() async throws {
    let fake = try await FakeHost(buildConfiguration: "debug")
    defer { fake.remove() }
    let xcrunPath = fake.directory.appendingPathComponent("xcrun").path
    try writeFakeXcrun(to: xcrunPath)

    let trace = try await runProcess(
      executable: try cliPath(),
      arguments: [
        "trace", "--host", fake.host.path, "--format", "json",
        "--xctrace-output", fake.directory.appendingPathComponent("trace.trace").path,
        "--xcrun", xcrunPath,
      ]
    )
    let check = try await processResult(
      executable: try cliPath(),
      arguments: [
        "check", "--allow-debug", "--host", fake.host.path, "--format", "json",
        "--budget", "wallClock:median:-1",
        "--xctrace-output", fake.directory.appendingPathComponent("check.trace").path,
        "--xcrun", xcrunPath,
      ]
    )
    let launches = try fake.launches()

    #expect(
      launches.map { $0.split(separator: " ").first } == ["list", "measure", "list", "measure"])
    #expect(launches[1].contains("--timeline"))
    #expect(!launches[3].contains("--timeline"))
    #expect(!launches.contains { $0.contains("--step") || $0.contains("--isolated") })
    #expect(trace.contains("\"Instruments trace\""))
    #expect(check.status == 20)
    #expect(check.output.contains("\"Instruments trace\""))
  }

  @Test(.timeLimit(.minutes(3)))
  func checkRefusesDebugHostsBeforeMeasuring() async throws {
    let fake = try await FakeHost(buildConfiguration: "debug")
    defer { fake.remove() }

    let check = try await processResult(
      executable: try cliPath(), arguments: ["check", "--host", fake.host.path])

    #expect(check.status == 2)
    #expect(check.errorOutput.contains("debug build"))
    #expect(try fake.launches().map { $0.split(separator: " ").first } == ["list"])
  }

  @Test(.timeLimit(.minutes(10)))
  func fixturePackageHostWorksThroughCLI() async throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package")
    try? FileManager.default.removeItem(atPath: scratchPath)

    _ = try await runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "build",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--product",
        "FixtureBenchmarks",
      ]
    )
    let binPath = try await runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "build",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--product",
        "FixtureBenchmarks",
        "--show-bin-path",
      ]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let hostPath = URL(fileURLWithPath: binPath)
      .appendingPathComponent("FixtureBenchmarks")
      .path

    let cli = try cliPath()
    let list = try await runProcess(
      executable: cli,
      arguments: [
        "list",
        "--host",
        hostPath,
        "--format",
        "json",
      ]
    )
    let run = try await runProcess(
      executable: cli,
      arguments: [
        "run",
        "--host",
        hostPath,
        "--format",
        "json",
        "--case",
        "Noop",
      ]
    )
    let failedCheck = try await processResult(
      executable: cli,
      arguments: [
        "check",
        "--allow-debug",
        "--host",
        hostPath,
        "--case",
        "Noop",
        "--budget",
        "wallClock:mean:-1",
        "--format",
        "json",
      ]
    )
    let invalidConfiguration = try await processResult(
      executable: cli,
      arguments: ["run", "--host", hostPath, "--case", "Noop", "--iterations", "nope"]
    )
    let missingBaseline = try await processResult(
      executable: cli,
      arguments: [
        "check", "--allow-debug", "--host", hostPath, "--case", "Noop", "--baseline",
        "/nonexistent/baseline.json",
      ]
    )
    // Each step runs in a host process of its own, so no other work shares
    // the counting pass and the counts are exact.
    let allocations = try await JSONDecoder().decode(
      ReportDocument.self,
      from: Data(
        runProcess(
          executable: cli,
          arguments: [
            "run", "--host", hostPath, "--case", "Allocate1000", "--warmup", "0",
            "--iterations", "1", "--format", "json",
          ]
        ).utf8)
    ).suites.first?.cases.first?.measurement

    let touched = try await JSONDecoder().decode(
      ReportDocument.self,
      from: Data(
        runProcess(
          executable: cli,
          arguments: [
            "run", "--host", hostPath, "--case", "Touch64MiB", "--warmup", "0",
            "--iterations", "1", "--batch-size", "1", "--format", "json",
          ]
        ).utf8)
    ).suites.first?.cases.first?.measurement

    #if canImport(Darwin) || os(Linux)
      // Pages the allocator already held count toward the starting footprint.
      #expect((touched?.statistics(for: .peakMemory)?.median ?? 0) >= Double(48 << 20))
    #endif
    #if canImport(Darwin)
      #expect(allocations?.statistics(for: .swiftAllocations)?.median == 1_000)
      #expect(allocations?.statistics(for: .swiftAllocatedBytes)?.median == 24_000)
    #else
      // A runtime without the instrumentation hooks leaves the counts out;
      // counts it reports must still be exact.
      if let counted = allocations?.statistics(for: .swiftAllocations) {
        #expect(counted.median == 1_000)
      }
    #endif
    #expect(list.contains("\"suite\" : \"Fixture\""))
    #expect(list.contains("\"caseName\" : \"Noop\""))
    #expect(run.contains("\"wallClock\""))
    #expect(run.contains("\"name\" : \"Noop\""))
    #expect(run.contains("\"measurement\""))
    #expect(failedCheck.status == 20)
    #expect(invalidConfiguration.status == 2)
    #expect(invalidConfiguration.errorOutput.contains("Invalid number 'nope' for --iterations"))
    #expect(missingBaseline.status == 2)
    #expect(failedCheck.output.contains("\"verdict\" : \"failed\""))
    #expect(failedCheck.errorOutput.contains("Regression check failed."))
  }
}
