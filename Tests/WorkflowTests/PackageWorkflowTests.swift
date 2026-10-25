// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

// Fixture deadlines include cold dependency builds on hosted runners.
@Suite("Package Workflow")
struct PackageWorkflowTests {
  @Test(.timeLimit(.minutes(1)))
  func subprocessCaptureHandlesLargeOutputAndFailures() throws {
    let script =
      "BEGIN { for (i = 0; i < 131072; i++) { printf \"o\"; printf \"e\" > \"/dev/stderr\" } }"
    let output = try runProcess(executable: "/usr/bin/awk", arguments: [script])
    #expect(output == String(repeating: "o", count: 131072))

    let failure = try runProcessFailure(
      executable: "/usr/bin/awk", arguments: [script + " END { exit 7 }"])
    #expect(
      failure == String(repeating: "o", count: 131072) + "\n"
        + String(repeating: "e", count: 131072))
  }

  @Test(.timeLimit(.minutes(3)))
  func cliProductsReportTheSameVersion() throws {
    let version = try runProcess(executable: cliPath(), arguments: ["--version"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let aliasVersion = try runProcess(
      executable: URL(fileURLWithPath: try cliPath()).deletingLastPathComponent()
        .appendingPathComponent("BenchmarkCLI").path,
      arguments: ["--version"]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(version.hasPrefix("swift-benchmark-cli "))
    #expect(version == aliasVersion)
  }

  @Test(.timeLimit(.minutes(3)))
  func cliReportsHelpAndInvalidCommands() throws {
    let help = try runProcess(executable: cliPath(), arguments: ["--help"])
    let invalidCommand = try processResult(
      executable: cliPath(), arguments: ["invalid-command"])

    #expect(help.contains("Commands:"))
    #expect(invalidCommand.status == 2)
  }

  @Test(.timeLimit(.minutes(3)))
  func runMeasuresEachStepInAHostProcessOfItsOwn() async throws {
    let fake = try await FakeHost(buildConfiguration: "release")
    defer { fake.remove() }

    let run = try runProcess(
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

    let trace = try runProcess(
      executable: try cliPath(),
      arguments: [
        "trace", "--host", fake.host.path, "--format", "json",
        "--xctrace-output", fake.directory.appendingPathComponent("trace.trace").path,
        "--xcrun", xcrunPath,
      ]
    )
    let check = try processResult(
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

    let check = try processResult(
      executable: try cliPath(), arguments: ["check", "--host", fake.host.path])

    #expect(check.status == 2)
    #expect(check.errorOutput.contains("debug build"))
    #expect(try fake.launches().map { $0.split(separator: " ").first } == ["list"])
  }

  @Test(.timeLimit(.minutes(10)))
  func fixturePackageHostWorksThroughCLI() throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package")
    try? FileManager.default.removeItem(atPath: scratchPath)

    _ = try runProcess(
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
    let binPath = try runProcess(
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
    let list = try runProcess(
      executable: cli,
      arguments: [
        "list",
        "--host",
        hostPath,
        "--format",
        "json",
      ]
    )
    let run = try runProcess(
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
    let failedCheck = try processResult(
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

    #expect(list.contains("\"suite\" : \"Fixture\""))
    #expect(list.contains("\"caseName\" : \"Noop\""))
    #expect(run.contains("\"wallClock\""))
    #expect(run.contains("\"name\" : \"Noop\""))
    #expect(run.contains("\"measurement\""))
    #expect(failedCheck.status == 20)
    #expect(failedCheck.output.contains("\"verdict\" : \"failed\""))
    #expect(failedCheck.errorOutput.contains("Regression check failed."))
  }

  @Test(.timeLimit(.minutes(10)))
  func fixturePackageCommandGeneratesHostWithoutUserBoilerplate() throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package-plugin")
    try? FileManager.default.removeItem(atPath: scratchPath)
    try FileManager.default.createDirectory(
      atPath: scratchPath,
      withIntermediateDirectories: true
    )
    let reportPath = URL(fileURLWithPath: scratchPath).appendingPathComponent("report.json").path
    let baselinePath = URL(fileURLWithPath: scratchPath).appendingPathComponent("baseline.json")
      .path
    let failedReportPath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("budget-failure.json").path
    let tracePath = URL(fileURLWithPath: scratchPath).appendingPathComponent("run.trace").path
    let testingReportPath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("testing-report.json")
      .path
    let testingBaselinePath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("testing-baseline.json")
      .path
    let testingTracePath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("testing.trace")
      .path
    let fakeXcrunPath = URL(fileURLWithPath: scratchPath).appendingPathComponent("fake-xcrun").path
    try writeFakeXcrun(to: fakeXcrunPath)

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "fast",
        "--format",
        "json",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "testingBridge",
        "--format",
        "json",
        "--output",
        testingReportPath,
        "--quiet",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "baseline",
        "write",
        "--input",
        testingReportPath,
        "--output",
        testingBaselinePath,
        "--quiet",
      ]
    )
    let testingCheck = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "check",
        "--allow-debug",
        "--tag",
        "testingBridge",
        "--baseline",
        testingBaselinePath,
        "--threshold",
        "1000000%",
        "--format",
        "json",
      ]
    )
    let testingDiff = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "diff",
        "--input",
        testingReportPath,
        "--baseline",
        testingBaselinePath,
        "--format",
        "json",
      ]
    )
    let testingTrace = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "trace",
        "--tag",
        "testingBridge",
        "--format",
        "json",
        "--xctrace-output",
        testingTracePath,
        "--xcrun",
        fakeXcrunPath,
      ]
    )
    let allList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--format",
        "json",
      ]
    )
    let testingList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "testingBridge",
        "--format",
        "json",
      ]
    )
    let standaloneList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "standalone",
        "--format",
        "json",
      ]
    )
    let run = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "library",
        "--format",
        "json",
      ]
    )
    let testingRun = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "testingBridge",
        "--format",
        "json",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "library",
        "--format",
        "json",
        "--output",
        reportPath,
        "--quiet",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "baseline",
        "write",
        "--input",
        reportPath,
        "--output",
        baselinePath,
        "--quiet",
      ]
    )
    let check = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "check",
        "--allow-debug",
        "--tag",
        "library",
        "--baseline",
        baselinePath,
        "--threshold",
        "1000000%",
        "--format",
        "json",
      ]
    )
    let diff = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "diff",
        "--input",
        reportPath,
        "--baseline",
        baselinePath,
        "--format",
        "json",
      ]
    )
    let failedCheck = try processResult(
      executable: "/usr/bin/env",
      arguments: [
        "swift", "package", "-q", "--package-path", fixturePath, "--scratch-path", scratchPath,
        "--allow-writing-to-directory", scratchPath, "benchmark", "check", "--allow-debug", "--tag",
        "library",
        "--baseline", baselinePath, "--budget", "wallClock:mean:-1", "--format", "json",
        "--output", failedReportPath, "--quiet",
      ]
    )
    let failedReport = try JSONDecoder().decode(
      ReportDocument.self, from: Data(contentsOf: URL(fileURLWithPath: failedReportPath)))
    let runReport = try JSONDecoder().decode(
      ReportDocument.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
    let rows = runReport.suites.flatMap(\.cases).flatMap(\.measurement.rows)
    let testingReport = try JSONDecoder().decode(
      ReportDocument.self, from: Data(contentsOf: URL(fileURLWithPath: testingReportPath)))
    let testingRows = testingReport.suites.flatMap(\.cases).flatMap(\.measurement.rows)
    let trace = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "trace",
        "--tag",
        "library",
        "--format",
        "json",
        "--xctrace-output",
        tracePath,
        "--xcrun",
        fakeXcrunPath,
      ]
    )

    #expect(list.contains("\"suite\" : \"LibraryFixture\""))
    #expect(list.contains("\"tags\""))
    #expect(allList.contains("\"suite\" : \"LibraryFixture\""))
    #expect(allList.contains("\"suite\" : \"TestingFixture\""))
    #expect(allList.contains("\"suite\" : \"StandaloneTestingBenchmarks\""))
    #expect(testingList.contains("\"caseName\" : \"Suite Noop\""))
    #expect(testingList.contains("\"caseName\" : \"Case Override\""))
    #expect(testingList.contains("\"testingBridge\""))
    #expect(!testingList.contains("Plain Test"))
    #expect(standaloneList.contains("\"caseName\" : \"Standalone Testing Benchmark\""))
    #expect(standaloneList.contains("\"standalone\""))
    #expect(run.contains("\"wallClock\""))
    #expect(run.contains("\"name\" : \"Noop\""))
    #expect(run.contains("\"tags\""))
    #expect(testingRun.contains("\"wallClock\""))
    #expect(testingRun.contains("\"name\" : \"Suite Noop\""))
    #expect(testingRun.contains("\"name\" : \"Case Override\""))
    #expect(testingRun.contains("\"TestingFixture\""))
    #expect(testingRun.contains("\"iterations\" : \"iterations(1)\""))
    #expect(testingRun.contains("\"iterations\" : \"iterations(2)\""))
    #expect(FileManager.default.fileExists(atPath: reportPath))
    #expect(FileManager.default.fileExists(atPath: baselinePath))
    #expect(FileManager.default.fileExists(atPath: testingReportPath))
    #expect(FileManager.default.fileExists(atPath: testingBaselinePath))
    #expect(check.contains("\"baseline\""))
    #expect(failedCheck.status != 0)
    #expect(failedReport.summary.failedBudgetCount == 1)
    #expect(runReport.summary.caseCount == 1)
    #expect(!rows.isEmpty)
    #expect(rows.allSatisfy { !$0.samples.isEmpty })
    #expect(!testingRows.isEmpty)
    #expect(testingRows.allSatisfy { !$0.samples.isEmpty })
    #expect(diff.contains("\"baseline\""))
    #expect(testingCheck.contains("\"baseline\""))
    #expect(testingDiff.contains("\"baseline\""))
    #expect(trace.contains("\"attributions\""))
    #expect(trace.contains("\"Instruments trace\""))
    #expect(trace.contains("\"xctrace\""))
    #expect(testingTrace.contains("\"attributions\""))
    #expect(testingTrace.contains("\"Instruments trace\""))
    #expect(testingTrace.contains("\"xctrace\""))
    #expect(FileManager.default.fileExists(atPath: tracePath))
    #expect(FileManager.default.fileExists(atPath: testingTracePath))
    let pluginVersion = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift", "package", "--package-path", fixturePath, "--scratch-path", scratchPath,
        "benchmark", "--version",
      ]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let cliVersion = try runProcess(executable: cliPath(), arguments: ["--version"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(pluginVersion == cliVersion)

  }

  // A cold Release fixture also compiles SwiftSyntax on hosted runners.
  @Test(.timeLimit(.minutes(15)))
  func fixturePackageCommandGeneratesReleaseHostWithoutPrebuild() throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package-plugin-release")
    try? FileManager.default.removeItem(atPath: scratchPath)
    try FileManager.default.createDirectory(
      atPath: scratchPath,
      withIntermediateDirectories: true
    )

    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--configuration",
        "debug",
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "fast",
        "--format",
        "json",
      ]
    )

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--configuration",
        "release",
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "fast",
        "--format",
        "json",
      ]
    )
    let run = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--configuration",
        "release",
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "fast",
        "--warmup",
        "0",
        "--iterations",
        "1",
        "--format",
        "json",
      ]
    )

    #expect(list.contains("\"suite\" : \"LibraryFixture\""))
    #expect(list.contains("\"caseName\" : \"Noop\""))
    #expect(run.contains("\"buildConfiguration\" : \"release\""))
  }

  @Test(.timeLimit(.minutes(10)), .serialized, arguments: [true, false])
  func fixturePackageCommandFindsCModuleMapsInExternalScratchPath(explicitModuleMap: Bool) throws {
    let layout = explicitModuleMap ? "explicit" : "generated"
    let sourceRoot = URL(fileURLWithPath: scratchPath("fixture-c-module-package-source-\(layout)"))
    let scratch = URL(
      fileURLWithPath: scratchPath("fixture-c-module-package-external-scratch-\(layout)"))
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: scratch)
    try FileManager.default.createDirectory(
      at: sourceRoot,
      withIntermediateDirectories: true
    )

    let dependency = sourceRoot.appendingPathComponent("CModuleDependency")
    let package = sourceRoot.appendingPathComponent("CModuleBenchmarkPackage")
    try writeCModuleDependencyPackage(at: dependency, explicitModuleMap: explicitModuleMap)
    try initializeGitRepository(at: dependency)
    try writeCModuleBenchmarkPackage(
      at: package,
      dependency: dependency,
      swiftBenchmarkRoot: repositoryRoot()
    )
    try FileManager.default.createDirectory(
      at: scratch,
      withIntermediateDirectories: true
    )

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        package.path,
        "--scratch-path",
        scratch.path,
        "--allow-writing-to-directory",
        scratch.path,
        "benchmark",
        "list",
        "--tag",
        "cModule",
        "--format",
        "json",
      ]
    )

    #expect(list.contains("\"suite\" : \"CModuleFixture\""))
    #expect(list.contains("\"caseName\" : \"CModuleNoop\""))
  }

  @Test(.timeLimit(.minutes(15)))
  func fixturePackageCommandLinksMixedLanguageResourceAndBinaryTargets() throws {
    #if os(macOS)
      let package = URL(fileURLWithPath: scratchPath("fixture-mixed-targets-package"))
      let scratch = URL(fileURLWithPath: scratchPath("fixture-mixed-targets-scratch"))
      try? FileManager.default.removeItem(at: package)
      try? FileManager.default.removeItem(at: scratch)
      try writeMixedTargetPackage(at: package, swiftBenchmarkRoot: repositoryRoot())

      // No write permission beyond the plugin's own work directory: the
      // host must build where the sandbox lets the plugin write.
      let run = try runProcess(
        executable: "/usr/bin/env",
        arguments: [
          "swift", "package", "-q", "--package-path", package.path, "--scratch-path", scratch.path,
          "benchmark", "run", "--warmup", "0", "--iterations", "2", "--format", "json",
        ]
      )

      #expect(run.contains("\"name\" : \"Total\""))
      #expect(run.contains("\"name\" : \"sameLine\""))
      #expect(run.contains("\"name\" : \"peakMemory\""))
    #endif
  }

  @Test(.timeLimit(.minutes(10)))
  func fixturePackageCommandReportsTestingBridgeDiagnostics() throws {
    let privatePackage = fixturePath("BenchmarkTestingPrivatePackage")
    let privateScratch = scratchPath("fixture-benchmark-testing-private")
    try? FileManager.default.removeItem(atPath: privateScratch)
    try FileManager.default.createDirectory(
      atPath: privateScratch,
      withIntermediateDirectories: true
    )
    let privateFailure = try runProcessFailure(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        privatePackage,
        "--scratch-path",
        privateScratch,
        "--allow-writing-to-directory",
        privateScratch,
        "benchmark",
        "list",
        "--format",
        "json",
      ]
    )

    let argumentsPackage = fixturePath("BenchmarkTestingArgumentsPackage")
    let argumentsScratch = scratchPath("fixture-benchmark-testing-arguments")
    try? FileManager.default.removeItem(atPath: argumentsScratch)
    try FileManager.default.createDirectory(
      atPath: argumentsScratch,
      withIntermediateDirectories: true
    )
    let argumentsList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        argumentsPackage,
        "--scratch-path",
        argumentsScratch,
        "--allow-writing-to-directory",
        argumentsScratch,
        "benchmark",
        "list",
        "--format",
        "json",
      ]
    )

    #expect(privateFailure.contains("private/fileprivate benchmark declarations cannot be bridged"))
    #expect(privateFailure.contains("make them internal"))
    #expect(argumentsList.contains("\"dimensionSizes\""))
    #expect(argumentsList.contains("1"))
    #expect(argumentsList.contains("2"))
  }

  private func runProcess(executable: String, arguments: [String]) throws -> String {
    let result = try processResult(executable: executable, arguments: arguments)
    guard result.status == 0 else {
      throw PackageWorkflowError(
        status: result.status,
        output: result.output,
        errorOutput: result.errorOutput
      )
    }
    return result.output
  }

  private func runProcessFailure(executable: String, arguments: [String]) throws -> String {
    let result = try processResult(executable: executable, arguments: arguments)
    guard result.status != 0 else {
      throw PackageWorkflowError(
        status: result.status,
        output: result.output,
        errorOutput: "Expected process to fail but it succeeded."
      )
    }
    return "\(result.output)\n\(result.errorOutput)"
  }

  private func processResult(executable: String, arguments: [String]) throws -> (
    status: Int32, output: String, errorOutput: String
  ) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-process-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputURL = directory.appendingPathComponent("stdout")
    let errorURL = directory.appendingPathComponent("stderr")
    try Data().write(to: outputURL)
    try Data().write(to: errorURL)
    // File capture lets verbose cold builds finish without filling unread pipes.
    let stdout = try FileHandle(forWritingTo: outputURL)
    defer { try? stdout.close() }
    let stderr = try FileHandle(forWritingTo: errorURL)
    defer { try? stderr.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = repositoryRoot()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return (
      process.terminationStatus,
      String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
      String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
    )
  }

  private func cliPath() throws -> String {
    #if DEBUG
      let configuration = "debug"
    #else
      let configuration = "release"
    #endif
    let path =
      ProcessInfo.processInfo.environment["SWIFT_BENCHMARK_CLI_PATH"]
      ?? repositoryRoot().appendingPathComponent(".build/\(configuration)/swift-benchmark-cli").path
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw PackageWorkflowError(
        status: 127, output: "", errorOutput: "Missing active CLI executable: \(path)")
    }
    return path
  }

  private func fixturePackagePath() -> String {
    fixturePath("BenchmarkPackage")
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func fixturePath(_ name: String) -> String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
      .path
  }

  private func scratchPath(_ name: String) -> String {
    repositoryRoot()
      .appendingPathComponent(".build/\(name)")
      .path
  }

  private func writeCModuleDependencyPackage(at package: URL, explicitModuleMap: Bool) throws {
    try writeFile(
      """
      // swift-tools-version: 6.3
      import PackageDescription

      let package = Package(
        name: "CModuleDependency",
        products: [
          .library(name: "CModuleDependency", targets: ["CModuleDependency"])
        ],
        targets: [
          .target(
            name: "CModuleDependency",
            path: "Sources/CModuleDependency",
            publicHeadersPath: "include"
          )
        ]
      )
      """,
      to: package.appendingPathComponent("Package.swift")
    )
    try writeFile(
      """
      #ifndef CMODULE_DEPENDENCY_H
      #define CMODULE_DEPENDENCY_H

      int c_module_dependency_value(void);

      #endif
      """,
      to: package.appendingPathComponent(
        "Sources/CModuleDependency/include/CModuleDependency.h"
      )
    )
    if explicitModuleMap {
      try writeFile(
        """
        module CModuleDependency {
          header "CModuleDependency.h"
          export *
        }
        """,
        to: package.appendingPathComponent(
          "Sources/CModuleDependency/include/module.modulemap"
        )
      )
    }
    try writeFile(
      """
      #include "CModuleDependency.h"

      int c_module_dependency_value(void) {
        return 42;
      }
      """,
      to: package.appendingPathComponent("Sources/CModuleDependency/CModuleDependency.c")
    )
  }

  /// A package whose benchmarks call C, Objective-C and C++ targets, a static
  /// XCFramework and a resource bundle, plus a test-target benchmark whose
  /// `@Test` attribute shares the function's line.
  private func writeMixedTargetPackage(at package: URL, swiftBenchmarkRoot: URL) throws {
    try writeFile(
      """
      // swift-tools-version: 6.3
      import PackageDescription

      let package = Package(
        name: "MixedTargets",
        platforms: [.macOS(.v15)],
        dependencies: [
          .package(name: "swift-benchmark", path: \(swiftStringLiteral(swiftBenchmarkRoot.path)))
        ],
        targets: [
          .target(name: "CCounter"),
          .target(name: "ObjCCounter"),
          .target(name: "CxxCounter"),
          .binaryTarget(name: "BinaryCounter", path: "BinaryCounter.xcframework"),
          .target(
            name: "MixedLibrary",
            dependencies: [
              "CCounter", "ObjCCounter", "CxxCounter", "BinaryCounter",
              .product(name: "Benchmark", package: "swift-benchmark"),
            ],
            resources: [.process("Resources")]
          ),
          .testTarget(
            name: "MixedTests",
            dependencies: [
              "MixedLibrary",
              .product(name: "BenchmarkTesting", package: "swift-benchmark"),
            ]
          ),
        ]
      )
      """,
      to: package.appendingPathComponent("Package.swift")
    )
    let files = [
      "Sources/CCounter/include/CCounter.h": "int c_counter_value(void);\n",
      "Sources/CCounter/CCounter.c":
        "#include \"CCounter.h\"\nint c_counter_value(void) { return 1; }\n",
      "Sources/ObjCCounter/include/ObjCCounter.h":
        "#import <Foundation/Foundation.h>\n@interface ObjCCounter : NSObject\n+ (NSInteger)value;\n@end\n",
      "Sources/ObjCCounter/ObjCCounter.m":
        "#import \"ObjCCounter.h\"\n@implementation ObjCCounter\n+ (NSInteger)value { return 2; }\n@end\n",
      "Sources/CxxCounter/include/CxxCounter.h":
        "#ifdef __cplusplus\nextern \"C\" {\n#endif\nint cxx_counter_value(void);\n#ifdef __cplusplus\n}\n#endif\n",
      "Sources/CxxCounter/CxxCounter.cpp":
        "#include \"CxxCounter.h\"\n#include <vector>\nint cxx_counter_value(void) { std::vector<int> v{1, 2}; return static_cast<int>(v.size()) + 1; }\n",
      "Sources/MixedLibrary/Resources/value.txt": "4\n",
      "Sources/MixedLibrary/Counters.swift": """
      import BinaryCounter
      import Benchmark
      import CCounter
      import CxxCounter
      import Foundation
      import ObjCCounter

      public enum Counters {
        public static func total() -> Int {
          let url = Bundle.module.url(forResource: "value", withExtension: "txt")!
          let text = try! String(contentsOf: url, encoding: .utf8)
          let resource = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))!
          return Int(c_counter_value()) + ObjCCounter.value() + Int(cxx_counter_value())
            + Int(binary_counter_value()) + resource
        }
      }

      @BenchmarkSuite("Mixed")
      struct MixedBenchmarks {
        @Benchmark("Total")
        func total() {
          precondition(Counters.total() == 15)
        }
      }
      """,
      "Tests/MixedTests/SameLine.swift": """
      import BenchmarkTesting
      import MixedLibrary
      import Testing

      struct SameLineBenchmarks {
        @Test(.benchmark()) func sameLine() { precondition(Counters.total() == 15) }
      }
      """,
      "binary/include/BinaryCounter.h": "int binary_counter_value(void);\n",
      "binary/include/module.modulemap":
        "module BinaryCounter {\n  header \"BinaryCounter.h\"\n  export *\n}\n",
      "binary/BinaryCounter.c":
        "#include \"BinaryCounter.h\"\nint binary_counter_value(void) { return 5; }\n",
    ]
    for (path, contents) in files {
      try writeFile(contents, to: package.appendingPathComponent(path))
    }

    let binary = package.appendingPathComponent("binary")
    let object = binary.appendingPathComponent("BinaryCounter.o").path
    let library = binary.appendingPathComponent("libBinaryCounter.a").path
    _ = try runProcess(
      executable: "/usr/bin/xcrun",
      arguments: [
        "clang", "-c", binary.appendingPathComponent("BinaryCounter.c").path, "-o", object,
        "-I", binary.appendingPathComponent("include").path,
        "-arch", "arm64", "-arch", "x86_64", "-mmacosx-version-min=15.0",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/xcrun", arguments: ["libtool", "-static", "-o", library, object])
    _ = try runProcess(
      executable: "/usr/bin/xcrun",
      arguments: [
        "xcodebuild", "-create-xcframework", "-library", library,
        "-headers", binary.appendingPathComponent("include").path,
        "-output", package.appendingPathComponent("BinaryCounter.xcframework").path,
      ]
    )
  }

  private func initializeGitRepository(at directory: URL) throws {
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", directory.path, "init", "-q"]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", directory.path, "checkout", "-q", "-B", "master"]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", directory.path, "add", "."]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "git",
        "-C",
        directory.path,
        "-c",
        "user.name=swift-benchmark-tests",
        "-c",
        "user.email=swift-benchmark-tests@example.invalid",
        "commit",
        "-q",
        "-m",
        "Initial test fixture",
      ]
    )
  }

  private func writeCModuleBenchmarkPackage(
    at package: URL,
    dependency: URL,
    swiftBenchmarkRoot: URL
  ) throws {
    let dependencyURL = dependency.absoluteURL
    try writeFile(
      """
      // swift-tools-version: 6.3
      import PackageDescription

      let package = Package(
        name: "CModuleBenchmarkPackage",
        platforms: [.macOS(.v15)],
        dependencies: [
          .package(name: "swift-benchmark", path: \(swiftStringLiteral(swiftBenchmarkRoot.path))),
          .package(url: \(swiftStringLiteral(dependencyURL.absoluteString)), branch: "master")
        ],
        targets: [
          .target(
            name: "CModuleBenchmarkLibrary",
            dependencies: [
              .product(name: "Benchmark", package: "swift-benchmark"),
              .product(name: "CModuleDependency", package: "CModuleDependency")
            ]
          )
        ]
      )
      """,
      to: package.appendingPathComponent("Package.swift")
    )
    try writeFile(
      """
      import Benchmark
      import CModuleDependency

      @BenchmarkSuite("CModuleFixture", .tag("cModule"))
      struct CModuleFixtureBenchmarks {
        @Benchmark("CModuleNoop")
        func noop() {
          blackHole(c_module_dependency_value())
        }
      }
      """,
      to: package.appendingPathComponent(
        "Sources/CModuleBenchmarkLibrary/LibraryBenchmarks.swift"
      )
    )
  }

  private func writeFile(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func swiftStringLiteral(_ value: String) -> String {
    var escaped = ""
    for character in value {
      switch character {
      case "\\":
        escaped += "\\\\"
      case "\"":
        escaped += "\\\""
      case "\n":
        escaped += "\\n"
      case "\r":
        escaped += "\\r"
      case "\t":
        escaped += "\\t"
      default:
        escaped.append(character)
      }
    }
    return "\"\(escaped)\""
  }

  private func writeFakeXcrun(to path: String) throws {
    let script = """
      #!/bin/sh
      output=""
      target_stdout=/dev/stdout
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --output) shift; output="$1" ;;
          --target-stdout) shift; target_stdout="$1" ;;
          --launch) shift; break ;;
        esac
        shift
      done
      executable="$1"
      shift
      if [ "$1" = "--" ]; then
        shift
      fi
      "$executable" "$@" > "$target_stdout" || exit 54
      if [ -n "$output" ]; then
        mkdir -p "$output"
      fi
      exit 0
      """
    try script.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: path
    )
  }
}

private struct PackageWorkflowError: Error, CustomStringConvertible {
  var status: Int32
  var output: String
  var errorOutput: String

  var description: String {
    "process failed with status \(status)\nstdout:\n\(output)\nstderr:\n\(errorOutput)"
  }
}

/// A shell script that answers the host protocol with a plan and a
/// measurement recorded in this process, and logs its arguments.
private struct FakeHost {
  let directory: URL
  let host: URL
  private let launchesURL: URL

  init(buildConfiguration: String) async throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-fake-host-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    host = directory.appendingPathComponent("host")
    launchesURL = directory.appendingPathComponent("launches")
    let planURL = directory.appendingPathComponent("plan.json")
    let measurementURL = directory.appendingPathComponent("measurement.json")
    var metadata = RunMetadata.local(id: "run:fake-host")
    metadata.buildConfiguration = buildConfiguration
    try await BenchmarkHost.output(
      discoveries: [FakeHostDiscovery.self], arguments: ["list"], metadata: metadata
    ).write(to: planURL)
    try await BenchmarkHost.output(
      discoveries: [FakeHostDiscovery.self], arguments: ["measure"], metadata: metadata
    ).write(to: measurementURL)
    try """
    #!/bin/sh
    echo "$*" >> '\(launchesURL.path)'
    command="$1"
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output" ]; then output="$2"; fi
      shift
    done
    if [ "$command" = list ]; then
      cp '\(planURL.path)' "$output"
    else
      cp '\(measurementURL.path)' "$output"
    fi
    """.write(to: host, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
  }

  /// The arguments of each launch, in order.
  func launches() throws -> [String] {
    try String(contentsOf: launchesURL, encoding: .utf8)
      .split(separator: "\n")
      .map(String.init)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private enum FakeHostDiscovery: _BenchmarkDiscovery {
  // swift-format-ignore: AlwaysUseLowerCamelCase
  static var __benchmarkSuites: [BenchmarkSuite] {
    [
      BenchmarkSuite(
        "FakeHost",
        configuration: BenchmarkConfiguration(
          warmup: .none, iterations: .iterations(1), batching: .fixed(1))
      ) {
        Benchmark("First") { blackHole(1) }
        Benchmark("Second") { blackHole(2) }
      }
    ]
  }
}
