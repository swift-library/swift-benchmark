// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

@Suite("Report Warnings")
struct ReportWarningTests {
  @Test
  func baselineFromOtherConditionsAndDebugBuildsAreRunWarnings() throws {
    let current = metadata(buildConfiguration: "debug", osVersion: "27.0", device: "Mac15,8")
    let previous = metadata(buildConfiguration: "release", osVersion: "26.6", device: "Mac15,8")
    let document = ReportDocument(
      metadata: current,
      results: [result(wallClock: Array(repeating: 1_000, count: 5))],
      baseline: BaselineDocument(
        metadata: previous, cases: [baselineCase(wallClock: Array(repeating: 1_000, count: 5))])
    )

    #expect(document.warnings.map(\.kind) == [.debugBuild, .runConditionMismatch])
    let mismatch = try #require(document.warnings.last?.message)
    #expect(mismatch.contains("OS version 26.6 → 27.0"))
    #expect(mismatch.contains("build configuration release → debug"))
    #expect(!mismatch.contains("device"))
    #expect(document.summary.warningCount == 2)
    #expect(
      ConsoleReportRenderer.render(document).contains("Warning: This run measured a debug build"))
  }

  @Test
  func comparisonsWhoseNoiseReachesTheThresholdAreFlagged() throws {
    let noisy = ReportDocument(
      metadata: metadata(),
      results: [result(wallClock: [100, 200, 100, 200, 100, 200])],
      baseline: BaselineDocument(cases: [baselineCase(wallClock: [150, 150, 150, 150, 150])])
    )
    let stable = ReportDocument(
      metadata: metadata(),
      results: [result(wallClock: [150, 151, 149, 150, 150])],
      baseline: BaselineDocument(cases: [baselineCase(wallClock: [150, 150, 150, 150, 150])])
    )

    let warning = try #require(noisy.suites.first?.cases.first?.warnings.first)
    #expect(warning.kind == .noisyComparison)
    #expect(warning.metric == .wallClock)
    #expect(warning.message.contains("threshold 10.0%"))
    #expect(stable.suites.first?.cases.first?.warnings == [])
  }

  @Test
  func absoluteThresholdsCompareNoiseInTheMetricsUnit() throws {
    let document = ReportDocument(
      metadata: metadata(),
      results: [result(wallClock: [100, 140, 100, 140, 100])],
      baseline: BaselineDocument(cases: [baselineCase(wallClock: [120, 120, 120, 120, 120])]),
      comparison: ComparisonPolicy(metricThresholds: [.wallClock: .absolute(15)])
    )

    #expect(document.suites.first?.cases.first?.warnings.map(\.kind) == [.noisyComparison])
  }

  @Test
  func comparedCasesWithFewTimedSamplesAreFlagged() throws {
    let compared = ReportDocument(
      metadata: metadata(),
      results: [result(wallClock: [100, 100])],
      baseline: BaselineDocument(cases: [baselineCase(wallClock: [100, 100])])
    )
    let notCompared = ReportDocument(
      metadata: metadata(), results: [result(wallClock: [100, 100])])

    #expect(compared.suites.first?.cases.first?.warnings.map(\.kind) == [.fewSamples])
    #expect(notCompared.suites.first?.cases.first?.warnings == [])
    #expect(notCompared.warnings == [])
  }

  @Test
  func checkGateRejectsDebugBuildsUnlessAllowed() throws {
    #expect(throws: CheckGateError.debugBuild) {
      try CheckGate.validate(buildConfiguration: "debug", allowDebug: false)
    }
    try CheckGate.validate(buildConfiguration: "debug", allowDebug: true)
    try CheckGate.validate(buildConfiguration: "release", allowDebug: false)
  }

  @Test
  func localMetadataNamesThePlatformCompilerAndMachine() {
    let local = RunMetadata.local(id: "run:local", buildConfiguration: "release")

    #expect(local.swiftVersion != "unknown")
    #expect(local.platform != local.osVersion)
    #expect(local.buildConfiguration == "release")
    #if os(macOS)
      #expect(local.platform == "macOS")
      #expect(local.device?.isEmpty == false)
    #endif
  }

  private func metadata(
    buildConfiguration: String = "release",
    osVersion: String = "27.0",
    device: String? = nil
  ) -> RunMetadata {
    RunMetadata(
      id: "run:warnings",
      swiftVersion: "6.4",
      packageIdentity: "swift-benchmark",
      platform: "macOS",
      architecture: "arm64",
      osVersion: osVersion,
      generatedAt: "2026-10-25T00:00:00Z",
      buildConfiguration: buildConfiguration,
      device: device
    )
  }

  private func result(wallClock: [Double]) -> BenchmarkResult {
    BenchmarkResult(
      suiteName: "Parser",
      caseName: "Tokenize",
      configuration: .default,
      measurement: Measurement(
        samples: wallClock.enumerated().map {
          Sample(iteration: $0.offset, values: [.wallClock: $0.element])
        })
    )
  }

  private func baselineCase(wallClock: [Double]) -> BaselineCase {
    BaselineCase(
      suiteName: "Parser",
      caseName: "Tokenize",
      measurement: Report.Measurement(
        samples: wallClock.enumerated().map { index, value in
          SampleReport(
            id: ReportID(rawValue: "sample:baseline.\(index)"),
            iterationID: ReportID(rawValue: "iteration:baseline.\(index)"),
            iteration: index,
            values: ["wallClock": value]
          )
        },
        metrics: [.wallClock]
      )
    )
  }
}
