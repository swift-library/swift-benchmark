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
    let earlierReport = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-earlier-report-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: earlierReport) }
    try Data(#"{"schemaVersion": 1, "suites": []}"#.utf8).write(to: earlierReport)
    let unreadableInput = try await processResult(
      executable: cliPath(), arguments: ["render", "--input", earlierReport.path])

    #expect(help.contains("Commands:"))
    #expect(invalidCommand.status == 2)
    #expect(missingInput.status == 2)
    #expect(unreadableInput.status == 2)
    #expect(unreadableInput.errorOutput.contains("generate it again"))
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
  func theInterposerCountsEachStepInASecondProcess() async throws {
    let fake = try await FakeHost(buildConfiguration: "release")
    defer { fake.remove() }

    _ = try await runProcess(
      executable: try cliPath(),
      arguments: [
        "run", "--host", fake.host.path, "--interposer", interposerPath(), "--iterations",
        "3", "--format", "json",
      ]
    )
    let measures = try fake.launches().dropFirst().map { $0.split(separator: " ") }

    #expect(measures.count == 4)
    for index in stride(from: 0, to: measures.count - 1, by: 2) {
      let timing = measures[index]
      let counting = measures[index + 1]
      let batchSize = counting.lastIndex(of: "--batch-size").map { counting[$0 + 1] }
      #expect(timing.contains("--timing-only"))
      #expect(counting.contains("--counting-only"))
      // The counting process calls the step in batches of the timed size.
      #expect(batchSize == "1")
      #expect(timing[2] == counting[2])
    }
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

    // With the interposer, each step is also counted in a process that loads
    // it, which counts every allocation through the system allocator.
    func counted(_ caseName: String) async throws -> Report.Measurement? {
      try await JSONDecoder().decode(
        ReportDocument.self,
        from: Data(
          runProcess(
            executable: cli,
            arguments: [
              "run", "--host", hostPath, "--interposer", interposerPath(), "--case", caseName,
              "--warmup", "0", "--iterations", "1", "--format", "json",
            ]
          ).utf8)
      ).suites.first?.cases.first?.measurement
    }
    let countedAllocations = try await counted("Allocate1000")
    let leaked = try await counted("Leak16Bytes")
    // A process the benchmark starts does not inherit the interposer.
    let spawned = try await counted("RunTrue")
    // Inputs from setup are made and freed outside the counted calls.
    let prepared = try await counted("SetupAllocates")
    let leakSites = try await JSONDecoder().decode(
      ReportDocument.self,
      from: Data(
        runProcess(
          executable: cli,
          arguments: [
            "run", "--host", hostPath, "--interposer", interposerPath(), "--allocation-sites",
            "--case", "Leak16Bytes", "--warmup", "0", "--iterations", "1", "--format", "json",
          ]
        ).utf8)
    ).suites.first?.cases.first?.measurement.rows.first?.allocationSites
    let sitesWithoutInterposer = try await processResult(
      executable: cli,
      arguments: ["run", "--host", hostPath, "--allocation-sites", "--case", "Leak16Bytes"]
    )
    let sitesInTrace = try await processResult(
      executable: cli,
      arguments: [
        "trace", "--host", hostPath, "--interposer", interposerPath(), "--allocation-sites",
        "--xctrace-output", scratchPath + "/sites.trace", "--case", "Leak16Bytes",
      ]
    )

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
      #expect(allocations?.statistics(for: .swiftAllocations) == nil)
    #endif
    #expect(allocations?.statistics(for: .heapAllocations) == nil)
    #expect(countedAllocations?.statistics(for: .swiftAllocations)?.median == 1_000)
    #expect(countedAllocations?.statistics(for: .swiftAllocatedBytes)?.median == 24_000)
    // Each object is one system allocation of its 24 bytes. The unoptimized
    // range loop allocates too, so the debug host counts more.
    #expect((countedAllocations?.statistics(for: .heapAllocations)?.median ?? 0) >= 1_000)
    #expect((countedAllocations?.statistics(for: .heapAllocatedBytes)?.median ?? 0) >= 24_000)
    #expect(countedAllocations?.statistics(for: .heapNetAllocations)?.median == 0)
    #expect(countedAllocations?.statistics(for: .wallClock) != nil)
    #expect(leaked?.statistics(for: .heapAllocations)?.median == 1)
    #expect(leaked?.statistics(for: .heapAllocatedBytes)?.median == 16)
    #expect(leaked?.statistics(for: .heapNetAllocations)?.median == 1)
    #expect(spawned?.statistics(for: .heapAllocations) != nil)
    #expect(prepared?.statistics(for: .heapAllocations)?.median == 0)
    #expect(prepared?.statistics(for: .heapNetAllocations)?.median == 0)
    #expect(prepared?.statistics(for: .swiftAllocations)?.median == 0)
    let leakStack = try #require(leakSites?.stacks.first)
    #expect(leakSites?.stacks.count == 1)
    #expect(leakStack.allocations == leakSites?.calls)
    #expect(leakStack.bytes == 16 * (leakSites?.calls ?? 0))
    #expect(leakStack.frames.contains { $0.contains("leak16Bytes") })
    #expect(!leakStack.frames.contains { $0.contains("BenchmarkWorkload") })
    #expect(sitesWithoutInterposer.status == 2)
    #expect(sitesWithoutInterposer.errorOutput.contains("--allocation-sites requires --interposer"))
    #expect(sitesInTrace.status == 2)
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
