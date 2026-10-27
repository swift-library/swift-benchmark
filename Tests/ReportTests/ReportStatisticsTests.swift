// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

@Suite("Report Statistics")
struct ReportStatisticsTests {
  @Test
  func noiseThatCanExplainAChangeDoesNotFailIt() throws {
    // The medians differ by 20%, but the two runs overlap so much that the
    // interval of the difference includes zero.
    let comparison = try #require(
      compare(
        current: [90, 130, 95, 125, 120, 100, 110, 140, 85, 135],
        baseline: [100, 80, 120, 90, 110, 85, 115, 95, 105, 75]
      ))

    #expect(comparison.delta > 0)
    #expect(comparison.percentageDelta > 10)
    #expect(comparison.significance == .notSignificant)
    #expect(comparison.confidenceInterval.map { $0.lowerBound < 0 && $0.upperBound > 0 } == true)
    #expect(comparison.verdict == .passed)
  }

  @Test
  func aSignificantChangePastItsThresholdFails() throws {
    let comparison = try #require(
      compare(
        current: [119, 121, 120, 118, 122, 120, 121, 119],
        baseline: [99, 101, 100, 98, 102, 100, 101, 99]
      ))

    #expect(comparison.significance == .significant)
    #expect(comparison.verdict == .failed)
    let interval = try #require(comparison.confidenceInterval)
    #expect(interval.level == 0.95)
    #expect(interval.lowerBound > 15 && interval.upperBound < 25)
  }

  @Test
  func singleValuesAreJudgedByTheThresholdAloneAndTheSameValuesGiveTheSameInterval() throws {
    let counted = try #require(compare(current: [1_200], baseline: [1_000]))
    let first = try #require(compare(current: [3, 5, 4, 6, 5], baseline: [4, 4, 5, 3, 4]))
    let second = try #require(compare(current: [3, 5, 4, 6, 5], baseline: [4, 4, 5, 3, 4]))

    #expect(counted.significance == .untested)
    #expect(counted.confidenceInterval == nil)
    #expect(counted.verdict == .failed)
    #expect(first.confidenceInterval == second.confidenceInterval)
  }

  @Test
  func severeAndMildOutliersAreCountedWithTukeyFences() {
    // The quartiles are 10 and 12, so values more than 3 outside them are
    // mild outliers and values more than 6 outside them severe ones.
    let statistics = Report.Statistics(values: [9, 10, 10, 11, 11, 12, 12, 16, 20])

    #expect(statistics.mildOutliers == 1)
    #expect(statistics.severeOutliers == 1)
  }

  @Test
  func valuesOneClockStepApartAreNotOutliers() {
    let quantized = Report.Statistics(values: [150, 151, 149, 150, 150, 150])
    let disturbed = Report.Statistics(values: [100, 100, 100, 100, 100, 400])

    #expect(quantized.mildOutliers == 0)
    #expect(quantized.severeOutliers == 0)
    #expect(disturbed.severeOutliers == 1)
  }

  @Test
  func manySevereOutliersWarn() throws {
    let disturbed = ReportDocument(
      metadata: metadata,
      results: [result([100, 101, 100, 99, 100, 101, 100, 99, 100, 400])],
      baseline: BaselineDocument(cases: [baselineCase([100, 100, 101, 99, 100])])
    )

    let warning = try #require(disturbed.suites.first?.cases.first?.warnings.first)
    #expect(warning.kind == .outliers)
    #expect(warning.message.contains("1 of 10 wallClock values"))
  }

  @Test(arguments: Report.Complexity.Model.allCases)
  func complexityFitsTheModelACurveFollows(_ model: Report.Complexity.Model) throws {
    func growth(_ size: Double) -> Double {
      switch model {
      case .constant: 5
      case .logarithmic: 3 * log2(size)
      case .linear: 2 * size
      case .linearithmic: size * log2(size)
      case .quadratic: 0.5 * size * size
      case .cubic: size * size * size
      }
    }
    let sizes = [8, 64, 512, 4_096]
    let document = ReportDocument(
      metadata: metadata,
      results: [
        BenchmarkResult(
          suiteName: "Growth",
          caseName: model.rawValue,
          configuration: .default,
          measurement: Measurement(
            rows: sizes.map { size in
              Measurement.Row(
                size: Benchmark.Scale(size),
                samples: [Sample(iteration: 0, values: [.wallClock: growth(Double(size))])])
            })
        )
      ]
    )
    let curve = try #require(
      document.suites.first?.cases.first?.dimensionCurves.first { $0.statistic == .median })

    #expect(curve.complexity?.model == model)
    #expect((curve.complexity?.normalizedRMS ?? 1) < 0.001)
  }

  @Test
  func complexityNeedsThreeSizes() throws {
    let document = ReportDocument(
      metadata: metadata,
      results: [
        BenchmarkResult(
          suiteName: "Growth",
          caseName: "Two sizes",
          configuration: .default,
          measurement: Measurement(
            rows: [1, 2].map { size in
              Measurement.Row(
                size: Benchmark.Scale(size),
                samples: [Sample(iteration: 0, values: [.wallClock: Double(size)])])
            })
        )
      ]
    )

    #expect(
      document.suites.first?.cases.first?.dimensionCurves.allSatisfy { $0.complexity == nil }
        == true)
  }

  @Test
  func markdownListsComplexityOfComparedMetricsOnly() {
    let document = ReportDocument(
      metadata: metadata,
      results: [
        BenchmarkResult(
          suiteName: "Growth",
          caseName: "Sizes",
          configuration: .default,
          measurement: Measurement(
            rows: [10, 100, 1_000].map { size in
              Measurement.Row(
                size: Benchmark.Scale(size),
                samples: [
                  Sample(
                    iteration: 0,
                    values: [.wallClock: Double(size), .contextSwitches: Double(size)])
                ])
            })
        )
      ]
    )

    let markdown = MarkdownReportRenderer.render(document)

    #expect(markdown.contains("| Growth › Sizes | wallClock | O(n) |"))
    #expect(!markdown.contains("| Growth › Sizes | contextSwitches |"))
  }

  @Test
  func markdownSummarizesComparisonsForPullRequests() throws {
    let compared = ReportDocument(
      metadata: metadata,
      results: [result([119, 121, 120, 118, 122, 120, 121, 119])],
      baseline: BaselineDocument(cases: [baselineCase([99, 101, 100, 98, 102, 100, 101, 99])])
    )
    let measured = ReportDocument(metadata: metadata, results: [result([100, 101, 99, 100, 100])])

    let comparison = MarkdownReportRenderer.render(compared)
    let measurement = MarkdownReportRenderer.render(measured)

    #expect(try ReportFormat(rawValue: "markdown")?.render(compared) == comparison)
    #expect(comparison.hasPrefix("## Benchmark report: failed\n"))
    #expect(
      comparison.contains(
        "| Case | Row | Metric | Baseline | Current | Change | 95% interval | Verdict |"))
    #expect(
      comparison.contains("| Parser › Tokenize |  | wallClock median | 100 ns | 120 ns | +20.0% |"))
    #expect(comparison.contains("| **failed** |"))
    #expect(measurement.contains("### Measurements"))
    #expect(measurement.contains("| Parser › Tokenize |  | wallClock | 100 ns | 101 ns |"))
  }

  private func compare(current: [Double], baseline: [Double]) -> BaselineComparison? {
    ReportDocument(
      metadata: metadata,
      results: [result(current)],
      baseline: BaselineDocument(cases: [baselineCase(baseline)])
    ).suites.first?.cases.first?.baselines.first
  }

  private var metadata: RunMetadata {
    RunMetadata(
      id: "run:statistics",
      swiftVersion: "6.4",
      packageIdentity: "swift-benchmark",
      platform: "macOS",
      architecture: "arm64",
      osVersion: "27.0",
      generatedAt: "2026-10-27T00:00:00Z",
      buildConfiguration: "release"
    )
  }

  private func result(_ wallClock: [Double]) -> BenchmarkResult {
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

  private func baselineCase(_ wallClock: [Double]) -> BaselineCase {
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
