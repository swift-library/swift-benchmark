// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

@Suite("Report Comparison")
struct ReportComparisonTests {
  @Test
  func eachDimensionRowIsComparedWithTheSameBaselineRow() throws {
    let document = ReportDocument(
      metadata: metadata,
      results: [dimensionResult(small: fiveSamples(100), large: fiveSamples(13_000))],
      baseline: BaselineDocument(cases: [
        dimensionBaseline(small: fiveSamples(100), large: fiveSamples(10_000))
      ])
    )
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.baselines.map(\.size?.rawValue) == [10, 1_000])
    #expect(report.baselines.map(\.verdict) == [.passed, .failed])
    #expect(report.verdictCauses.first?.size == Benchmark.Scale(1_000))
    #expect(report.verdictCauses.first?.message.contains("at size 1000") == true)
  }

  @Test
  func stableRowsOfDifferentSizesAreNotReportedAsNoise() throws {
    let document = ReportDocument(
      metadata: metadata,
      results: [dimensionResult(small: fiveSamples(100), large: fiveSamples(10_000))],
      baseline: BaselineDocument(cases: [
        dimensionBaseline(small: fiveSamples(100), large: fiveSamples(10_000))
      ])
    )

    #expect(document.suites.first?.cases.first?.warnings == [])
  }

  @Test
  func budgetsFollowTheMeasuredMetricsDirection() throws {
    let throughput = Benchmark.Metric(name: "throughput", unit: .count, direction: .higherIsBetter)
    let policy = try ComparisonArguments.policy(
      statistic: nil, thresholds: [], budgets: ["throughput:median:100"], caseBudgets: [])

    func verdict(_ value: Double) throws -> ReportVerdict {
      let document = ReportDocument(
        metadata: metadata,
        results: [
          BenchmarkResult(
            suiteName: "Parser",
            caseName: "Stream",
            configuration: .default,
            measurement: Measurement(samples: [Sample(iteration: 0, values: [throughput: value])])
          )
        ],
        comparison: policy
      )
      return try #require(document.suites.first?.cases.first?.budgets.first?.verdict)
    }

    #expect(try verdict(80) == .failed)
    #expect(try verdict(120) == .passed)
  }

  @Test
  func customMetricAmountsTakeNoUnitSuffix() {
    #expect(
      throws: ComparisonArgumentError.unitForCustomMetric("--budget", "4KiB", "bytesWritten")
    ) {
      try ComparisonArguments.policy(
        statistic: nil, thresholds: [], budgets: ["bytesWritten:median:4KiB"], caseBudgets: [])
    }
    #expect(
      throws: ComparisonArgumentError.unitForCustomMetric("--threshold", "5ms", "bytesWritten")
    ) {
      try ComparisonArguments.policy(
        statistic: nil, thresholds: ["bytesWritten=5ms"], budgets: [], caseBudgets: [])
    }
  }

  @Test
  func eventBuiltRowsListOnlyTheirOwnMetrics() async throws {
    let parsedBytes = Benchmark.Metric(name: "parsedBytes", unit: .bytes)
    let suite = BenchmarkSuite(
      "Rows",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Parse", arguments: [1, 512]) { bytes in
        if bytes > 1 {
          Benchmark.record(Double(bytes), for: parsedBytes)
        }
      }
    }
    let recorder = ReportRecorder()

    let results = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false)
      .run(suite, eventRecorders: [recorder])
    let direct = ReportDocument(metadata: metadata, results: results)
    let eventBuilt = await recorder.document(metadata: metadata)
    let directRows = try #require(direct.suites.first?.cases.first?.measurement.rows)
    let eventRows = try #require(eventBuilt.suites.first?.cases.first?.measurement.rows)

    #expect(
      eventRows.map { $0.metrics.map(\.name) } == [["wallClock"], ["parsedBytes", "wallClock"]])
    #expect(eventRows.map(\.metrics) == directRows.map(\.metrics))
  }

  private var metadata: RunMetadata {
    RunMetadata(
      id: "run:comparison",
      swiftVersion: "6.4",
      packageIdentity: "swift-benchmark",
      platform: "macOS",
      architecture: "arm64",
      osVersion: "27.0",
      generatedAt: "2026-10-25T00:00:00Z",
      buildConfiguration: "release"
    )
  }

  /// Five identical samples, the fewest that comparisons accept without a
  /// few-samples warning.
  private func fiveSamples(_ value: Double) -> [Double] {
    Array(repeating: value, count: 5)
  }

  private func dimensionResult(small: [Double], large: [Double]) -> BenchmarkResult {
    BenchmarkResult(
      suiteName: "Arrays",
      caseName: "Sort",
      configuration: .default,
      measurement: Measurement(rows: [
        Measurement.Row(size: Benchmark.Scale(10), samples: samples(small)),
        Measurement.Row(size: Benchmark.Scale(1_000), samples: samples(large)),
      ])
    )
  }

  private func dimensionBaseline(small: [Double], large: [Double]) -> BaselineCase {
    BaselineCase(
      suiteName: "Arrays",
      caseName: "Sort",
      measurement: Report.Measurement(rows: [
        Report.Measurement.Row(
          size: Benchmark.Scale(10), samples: sampleReports(small), metrics: [.wallClock]),
        Report.Measurement.Row(
          size: Benchmark.Scale(1_000), samples: sampleReports(large), metrics: [.wallClock]),
      ])
    )
  }

  private func samples(_ wallClock: [Double]) -> [Sample] {
    wallClock.enumerated().map { Sample(iteration: $0.offset, values: [.wallClock: $0.element]) }
  }

  private func sampleReports(_ wallClock: [Double]) -> [SampleReport] {
    wallClock.enumerated().map { index, value in
      SampleReport(
        id: ReportID(rawValue: "sample:baseline.\(index)"),
        iterationID: ReportID(rawValue: "iteration:baseline.\(index)"),
        iteration: index,
        values: ["wallClock": value]
      )
    }
  }
}
