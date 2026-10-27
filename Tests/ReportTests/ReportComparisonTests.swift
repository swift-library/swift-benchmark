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

    let results = try await BenchmarkRunner(
      cpuClock: nil, countsProcessEvents: false, countsAllocations: false
    )
    .run(suite, eventRecorders: [recorder])
    let direct = ReportDocument(metadata: metadata, results: results)
    let eventBuilt = await recorder.document(metadata: metadata)
    let directRows = try #require(direct.suites.first?.cases.first?.measurement.rows)
    let eventRows = try #require(eventBuilt.suites.first?.cases.first?.measurement.rows)

    #expect(
      eventRows.map { $0.metrics.map(\.name) } == [["wallClock"], ["parsedBytes", "wallClock"]])
    #expect(eventRows.map(\.metrics) == directRows.map(\.metrics))
  }

  @Test
  func metricsTheEnvironmentMovesAreJudgedOnlyOnRequest() throws {
    func result(contextSwitches: Double) -> BenchmarkResult {
      BenchmarkResult(
        suiteName: "Parser",
        caseName: "Tokenize",
        configuration: .default,
        measurement: Measurement(samples: [
          Sample(iteration: 0, values: [.wallClock: 1_000, .contextSwitches: contextSwitches])
        ])
      )
    }
    let baseline = BaselineDocument(
      document: ReportDocument(metadata: .fixture(), results: [result(contextSwitches: 1)]))

    let unrequested = ReportDocument(
      metadata: .fixture(), results: [result(contextSwitches: 50)], baseline: baseline)
    let requested = ReportDocument(
      metadata: .fixture(),
      results: [result(contextSwitches: 50)],
      baseline: baseline,
      comparison: ComparisonPolicy(metricThresholds: [.contextSwitches: .relativePercentage(10)])
    )

    #expect(unrequested.suites.first?.cases.first?.baselines.map(\.metric) == [.wallClock])
    #expect(
      requested.suites.first?.cases.first?.baselines.contains {
        $0.metric == .contextSwitches && $0.verdict == .failed
      } == true)
  }

  @Test
  func eventBuiltArgumentRowsKeepTheOrderTheyWereMeasuredIn() async throws {
    let names = (0..<12).map { "row \(11 - $0)" }
    let suite = BenchmarkSuite(
      "Rows",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Parse", arguments: names) { name in blackHole(name) }
    }
    let recorder = ReportRecorder()

    _ = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false)
      .run(suite, eventRecorders: [recorder])
    let rows = try #require(
      await recorder.document(metadata: metadata).suites.first?.cases.first?.measurement.rows)

    #expect(rows.map { $0.arguments.map(\.label).joined() } == names)
  }

  @Test
  func baselineAndBudgetStatisticsPreserveTypedVerdictCauses() throws {
    let result = BenchmarkResult(
      suiteName: "Parser",
      caseName: "ParseDocument",
      sourceLocation: BenchmarkSourceLocation(
        fileID: "ParserBenchmarks/ParserBenchmarks.swift",
        filePath: "/tmp/ParserBenchmarks.swift",
        line: 42,
        column: 5
      ),
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(3), batching: .fixed(1)),
      measurement: Measurement(samples: wallClockSamples([1_000, 2_000, 3_000]))
    )
    let baseline = BaselineDocument(cases: [
      baselineCase("Parser", "ParseDocument", wallClock: [1_800])
    ])

    let document = ReportDocument(
      metadata: .fixture(),
      results: [result],
      baseline: baseline,
      comparison: ComparisonPolicy(
        statistic: .p95,
        threshold: .relativePercentage(10),
        metricThresholds: [.wallClock: .absolute(1_000)],
        budgets: [
          BudgetPolicy(metric: .wallClock, statistic: .mean, limit: 2_500),
          BudgetPolicy(metric: .wallClock, statistic: .p95, limit: 2_500),
        ]
      )
    )
    let report = try #require(document.suites.first?.cases.first)
    let comparison = try #require(report.baselines.first)

    #expect(comparison.metric == .wallClock)
    #expect(comparison.statistic == .p95)
    #expect(comparison.current == 2_900)
    #expect(comparison.baseline == 1_800)
    #expect(comparison.threshold == .absolute(1_000))
    #expect(comparison.verdict == .failed)
    #expect(report.budgets.map(\.verdict) == [.passed, .failed])
    #expect(report.verdict == .failed)
    #expect(report.verdictCauses.map(\.kind) == [.baselineRegression, .budgetExceeded])
    #expect(report.verdictCauses.map(\.statistic) == [.p95, .p95])
    #expect(document.summary.failedRegressionCount == 1)
    #expect(document.summary.failedBudgetCount == 1)
  }

  @Test
  func everySharedMetricIsComparedAndDirectionDecidesRegression() throws {
    let throughput = Benchmark.Metric(
      name: "throughput", unit: .count, direction: .higherIsBetter)
    let allocations = Benchmark.Metric.swiftAllocations
    let result = BenchmarkResult(
      suiteName: "Parser",
      caseName: "Tokenize",
      configuration: .default,
      measurement: Measurement(samples: [
        Sample(iteration: 0, values: [.wallClock: 1_000, throughput: 80, allocations: 4])
      ])
    )
    let baseline = BaselineDocument(cases: [
      BaselineCase(
        suiteName: "Parser",
        caseName: "Tokenize",
        measurement: Report.Measurement(
          samples: [
            SampleReport(
              id: "sample:baseline.0", iterationID: "iteration:baseline.0", iteration: 0,
              values: ["wallClock": 1_000, "throughput": 100])
          ],
          metrics: [.wallClock, throughput]
        )
      )
    ])

    let document = ReportDocument(metadata: .fixture(), results: [result], baseline: baseline)
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.baselines.map(\.metric.name) == ["throughput", "wallClock"])
    #expect(report.baselines.map(\.verdict) == [.failed, .passed])
    #expect(report.baselines.first?.percentageDelta == -20)
  }

  @Test
  func budgetOnUnmeasuredMetricIsNotCompared() throws {
    let document = ReportDocument(
      metadata: .fixture(),
      results: [
        BenchmarkResult(
          suiteName: "Parser",
          caseName: "Tokenize",
          configuration: .default,
          measurement: Measurement(samples: wallClockSamples([2_000]))
        )
      ],
      comparison: ComparisonPolicy(budgets: [
        BudgetPolicy(
          metric: .swiftAllocations,
          statistic: .median,
          limit: 0
        )
      ])
    )
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.budgets.first?.verdict == .notCompared)
    #expect(report.budgets.first?.actual == nil)
    #expect(report.verdict == .notCompared)
  }

  @Test
  func comparingExistingDocumentAppliesBaselineAndBudgetsWithoutChangingSamples() throws {
    let original = ReportDocument(
      metadata: .fixture(),
      results: [
        BenchmarkResult(
          suiteName: "Parser",
          caseName: "Tokenize",
          configuration: .default,
          measurement: Measurement(samples: wallClockSamples([2_000]))
        )
      ]
    )
    let baseline = BaselineDocument(cases: [
      baselineCase("Parser", "Tokenize", wallClock: [1_000])
    ])
    let compared = original.comparing(
      baseline: baseline,
      comparison: ComparisonPolicy(budgets: [
        BudgetPolicy(metric: .wallClock, statistic: .mean, limit: 1_500)
      ])
    )
    let report = try #require(compared.suites.first?.cases.first)

    #expect(report.samples.map { $0.value(for: .wallClock) } == [2_000])
    #expect(report.baselines.first?.verdict == .failed)
    #expect(report.budgets.first?.verdict == .failed)
    #expect(report.verdictCauses.map(\.kind) == [.baselineRegression, .budgetExceeded])
    #expect(compared.summary.failedRegressionCount == 1)
    #expect(compared.summary.failedBudgetCount == 1)
  }

  @Test
  func absoluteThresholdAllowsSmallRegression() throws {
    let comparison = BaselineComparison(
      metric: .wallClock,
      statistic: .median,
      current: 1_100,
      baseline: 1_000,
      threshold: .absolute(100)
    )

    #expect(comparison.verdict == .passed)
    #expect(comparison.delta == 100)
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
