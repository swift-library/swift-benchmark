// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

@Suite("Comparison Arguments")
struct ComparisonArgumentsTests {
  @Test
  func defaultsCompareMediansWithATenPercentThreshold() throws {
    let policy = try ComparisonArguments.policy(
      statistic: nil, thresholds: [], budgets: [], caseBudgets: [])

    #expect(policy == .default)
    #expect(policy.statistic == .median)
    #expect(policy.threshold(for: .wallClock) == .relativePercentage(10))
  }

  @Test
  func thresholdsAndBudgetsParseUnitsPerMetric() throws {
    let policy = try ComparisonArguments.policy(
      statistic: "p95",
      thresholds: ["5%", "wallClock=250us", "allocations=0"],
      budgets: ["wallClock:p95:2ms"],
      caseBudgets: ["Parser:Parse Document:allocatedBytes:median:4KiB"]
    )

    #expect(policy.statistic == .p95)
    #expect(policy.threshold == .relativePercentage(5))
    #expect(policy.threshold(for: .wallClock) == .absolute(250_000))
    #expect(
      policy.threshold(for: Benchmark.Metric(name: "allocations", unit: .count)) == .absolute(0))
    #expect(policy.budgets.map(\.limit) == [2_000_000, 4_096])
    #expect(policy.budgets.last?.caseName == "Parse Document")
    #expect(policy.budgets.last?.metric.unit == .bytes)
    #expect(policy.budgets.last?.statistic == .median)
  }

  @Test
  func invalidValuesExplainTheExpectedForm() {
    #expect(throws: ComparisonArgumentError.invalidStatistic("average")) {
      try ComparisonArguments.policy(
        statistic: "average", thresholds: [], budgets: [], caseBudgets: [])
    }
    #expect(throws: ComparisonArgumentError.absoluteThresholdNeedsMetric("5ms")) {
      try ComparisonArguments.policy(
        statistic: nil, thresholds: ["5ms"], budgets: [], caseBudgets: [])
    }
    #expect(throws: ComparisonArgumentError.unitMismatch("--budget", "4KiB", .nanoseconds)) {
      try ComparisonArguments.policy(
        statistic: nil, thresholds: [], budgets: ["wallClock:p95:4KiB"], caseBudgets: [])
    }
    #expect(throws: ComparisonArgumentError.invalidBudget("--budget", "p95:2000")) {
      try ComparisonArguments.policy(
        statistic: nil, thresholds: [], budgets: ["p95:2000"], caseBudgets: [])
    }
  }

  @Test
  func baselineThatCannotBeDecodedAsksToRecordItAgain() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-old-baseline-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let oldBaseline = """
      {"cases": [{"suiteName": "A", "caseName": "B", "meanNanoseconds": 1}]}
      """
    try Data(oldBaseline.utf8).write(to: url)

    #expect(throws: BaselineReadError.unreadable(path: url.path)) {
      try BaselineDocument.read(path: url.path)
    }
  }

  @Test
  func missingBaselineIsReportedAsUnavailable() throws {
    let path = "/nonexistent/baseline.json"

    let error = #expect(throws: BaselineReadError.self) {
      try BaselineDocument.read(path: path)
    }

    guard case .unavailable(path, _) = error else {
      Issue.record("Expected an unavailable baseline, got \(String(describing: error))")
      return
    }
  }
}
