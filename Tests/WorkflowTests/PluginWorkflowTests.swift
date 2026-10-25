// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

// Fixture deadlines include cold dependency builds on hosted runners.
@Suite("Plugin Workflow")
struct PluginWorkflowTests {
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
      arguments: swiftPackageBenchmark(
        ["list", "--tag", "fast", "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "run", "--tag", "testingBridge", "--format", "json", "--output", testingReportPath,
          "--quiet",
        ],
        package: fixturePath, scratch: scratchPath
      )
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "baseline", "write", "--input", testingReportPath, "--output", testingBaselinePath,
          "--quiet",
        ],
        package: fixturePath, scratch: scratchPath
      )
    )
    let testingCheck = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "check", "--allow-debug", "--tag", "testingBridge", "--baseline", testingBaselinePath,
          "--threshold", "1000000%", "--format", "json",
        ],
        package: fixturePath, scratch: scratchPath
      )
    )
    let testingDiff = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "diff", "--input", testingReportPath, "--baseline", testingBaselinePath, "--format",
          "json",
        ],
        package: fixturePath, scratch: scratchPath
      )
    )
    let testingTrace = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "trace", "--tag", "testingBridge", "--format", "json", "--xctrace-output",
          testingTracePath, "--xcrun", fakeXcrunPath,
        ],
        package: fixturePath, scratch: scratchPath
      )
    )
    let allList = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["list", "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    let testingList = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["list", "--tag", "testingBridge", "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    let standaloneList = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["list", "--tag", "standalone", "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    let run = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["run", "--tag", "library", "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    let testingRun = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["run", "--tag", "testingBridge", "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["run", "--tag", "library", "--format", "json", "--output", reportPath, "--quiet"],
        package: fixturePath, scratch: scratchPath
      )
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["baseline", "write", "--input", reportPath, "--output", baselinePath, "--quiet"],
        package: fixturePath, scratch: scratchPath
      )
    )
    let check = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "check", "--allow-debug", "--tag", "library", "--baseline", baselinePath, "--threshold",
          "1000000%", "--format", "json",
        ],
        package: fixturePath, scratch: scratchPath
      )
    )
    let diff = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["diff", "--input", reportPath, "--baseline", baselinePath, "--format", "json"],
        package: fixturePath, scratch: scratchPath
      )
    )
    let failedCheck = try processResult(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        [
          "check", "--allow-debug", "--tag", "library", "--baseline", baselinePath,
          "--budget", "wallClock:mean:-1", "--format", "json", "--output", failedReportPath,
          "--quiet",
        ],
        package: fixturePath, scratch: scratchPath
      )
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
      arguments: swiftPackageBenchmark(
        [
          "trace", "--tag", "library", "--format", "json", "--xctrace-output", tracePath, "--xcrun",
          fakeXcrunPath,
        ],
        package: fixturePath, scratch: scratchPath
      )
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
      arguments: swiftPackageBenchmark(
        ["list", "--tag", "fast", "--format", "json"],
        package: fixturePath, scratch: scratchPath, configuration: "debug"
      )
    )

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["list", "--tag", "fast", "--format", "json"],
        package: fixturePath, scratch: scratchPath, configuration: "release"
      )
    )
    let run = try runProcess(
      executable: "/usr/bin/env",
      arguments: swiftPackageBenchmark(
        ["run", "--tag", "fast", "--warmup", "0", "--iterations", "1", "--format", "json"],
        package: fixturePath, scratch: scratchPath, configuration: "release"
      )
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
      arguments: swiftPackageBenchmark(
        ["list", "--tag", "cModule", "--format", "json"],
        package: package.path, scratch: scratch.path
      )
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
      arguments: swiftPackageBenchmark(
        ["list", "--format", "json"],
        package: privatePackage, scratch: privateScratch
      )
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
      arguments: swiftPackageBenchmark(
        ["list", "--format", "json"],
        package: argumentsPackage, scratch: argumentsScratch
      )
    )

    #expect(privateFailure.contains("private/fileprivate benchmark declarations cannot be bridged"))
    #expect(privateFailure.contains("make them internal"))
    #expect(argumentsList.contains("\"dimensionSizes\""))
    #expect(argumentsList.contains("1"))
    #expect(argumentsList.contains("2"))
  }
}
