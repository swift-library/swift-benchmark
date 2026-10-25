// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Instruments
import Report
import Testing

@Suite("Report Document")
struct ReportDocumentTests {
  @Test
  func reportDocumentCorrelatesBenchmarkBaselineAndTimeline() throws {
    let result = BenchmarkResult(
      suiteName: "Parser",
      caseName: "ParseDocument",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(2), batching: .fixed(1)),
      tags: ["parser", "critical"],
      measurement: Measurement(samples: wallClockSamples([1_000, 3_000]))
    )
    let metadata = RunMetadata.fixture()
    let timeline = makeTimeline()
    let attribution = TimelineCorrelator.attribution(
      from: timeline,
      runID: metadata.id,
      suiteName: "Parser",
      caseName: "ParseDocument",
      iteration: 1
    )
    let baseline = BaselineDocument(cases: [
      baselineCase("Parser", "ParseDocument", wallClock: [1_000])
    ])

    let document = ReportDocument(
      metadata: metadata,
      results: [result],
      baseline: baseline,
      comparison: ComparisonPolicy(statistic: .mean, threshold: .relativePercentage(50)),
      attributions: [attribution]
    )

    let report = try #require(document.suites.first?.cases.first)
    #expect(document.summary.verdict == .failed)
    #expect(report.tags == ["parser", "critical"])
    #expect(report.samples.map { $0.value(for: .wallClock) } == [1_000, 3_000])
    #expect(report.baselines.first?.delta == 1_000)
    #expect(report.baselines.first?.percentageDelta == 100)
    #expect(report.verdict == .failed)
    #expect(report.attribution?.spans.map(\.name) == ["ParseAST"])
    #expect(report.attribution?.events.map(\.name) == ["CacheMiss"])
  }

  @Test
  func jsonAndConsoleRenderTheSameReportDocument() throws {
    let document = ReportDocument(
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

    let json = try JSONReportRenderer.render(document)
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: Data(json.utf8))
    let console = ConsoleReportRenderer.render(document)

    #expect(decoded == document)
    #expect(console.contains("Tokenize: wallClock median 2.000 us, p95 2.000 us"))
  }

  @Test
  func reportRecorderBuildsReportDocumentFromBenchmarkEventStream() async throws {
    let suite = BenchmarkSuite(
      "Events",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(1)),
      traits: [.tag("event-report")]
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let recorder = ReportRecorder()
    let runner = BenchmarkRunner(
      clock: ReportStepClock(step: 11), cpuClock: nil, countsAllocations: false)

    let results = try await runner.run(suite, eventRecorders: [recorder])
    let metadata = RunMetadata.fixture()
    let direct = ReportDocument(metadata: metadata, results: results)
    let eventBuilt = await recorder.document(metadata: metadata)
    let directReport = try #require(direct.suites.first?.cases.first)
    let eventReport = try #require(eventBuilt.suites.first?.cases.first)

    #expect(eventReport.name == directReport.name)
    #expect(eventReport.tags == ["event-report"])
    #expect(eventReport.samples.map { $0.value(for: .wallClock) } == [11, 11])
    #expect(eventReport.measurement == directReport.measurement)
    #expect(eventReport.configuration == directReport.configuration)
    #expect(eventReport.sourceLocation == directReport.sourceLocation)
  }

  @Test
  func jsonFixtureRoundTripsAndExposesVerdictCauses() throws {
    let fixture = try Data(contentsOf: reportFixtureURL("report.json"))
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: fixture)
    let encoded = try JSONReportRenderer.render(decoded)
    let roundTripped = try JSONDecoder().decode(ReportDocument.self, from: Data(encoded.utf8))
    let report = try #require(roundTripped.suites.first?.cases.first)

    #expect(roundTripped == decoded)
    #expect(roundTripped.summary.verdict == .failed)
    #expect(report.tags == [])
    #expect(report.verdictCauses.map(\.kind) == [.budgetExceeded])
    #expect(report.verdictCauses.first?.metric == .wallClock)
    #expect(report.sourceLocation?.line == 42)
    #expect(report.samples.map { $0.value(for: .wallClock) } == [1_000, 2_000])
    #expect(report.measurement.statistics(for: .wallClock)?.p95 == 1_950)
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
    let allocations = Benchmark.Metric(name: "allocations", unit: .count)
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
          metric: Benchmark.Metric(name: "allocations", unit: .count),
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
  func speedscopeRendererExportsAttributionFramesFromReportDocument() throws {
    let result = BenchmarkResult(
      suiteName: "Parser",
      caseName: "ParseDocument",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1)),
      measurement: Measurement(samples: [Sample(iteration: 1, values: [.wallClock: 20])])
    )
    let metadata = RunMetadata.fixture()
    let attribution = TimelineCorrelator.attribution(
      from: makeTimeline(),
      runID: metadata.id,
      suiteName: "Parser",
      caseName: "ParseDocument",
      iteration: 1
    )
    let document = ReportDocument(
      metadata: metadata,
      results: [result],
      attributions: [attribution]
    )
    let output = try SpeedscopeReportRenderer.render(document)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
    )
    let shared = try #require(object["shared"] as? [String: Any])
    let frames = try #require(shared["frames"] as? [[String: Any]])
    let profiles = try #require(object["profiles"] as? [[String: Any]])

    #expect(object["$schema"] as? String == "https://www.speedscope.app/file-format-schema.json")
    #expect(frames.map { $0["name"] as? String } == ["ParseAST"])
    #expect(
      profiles.first?["name"] as? String == "Parser.ParseDocument sample:parser.parsedocument.1")
  }

  @Test
  func timelineCorrelatorIncludesChildSpansAndEventsUnderCorrelatedParent() throws {
    let metadata = RunMetadata.fixture()
    let attribution = TimelineCorrelator.attribution(
      from: makeNestedTimeline(),
      runID: metadata.id,
      suiteName: "Parser",
      caseName: "ParseDocument",
      iteration: 1
    )

    #expect(attribution.spans.map(\.name) == ["IterationRoot", "ParseAST"])
    #expect(attribution.events.map(\.name) == ["CacheMiss"])
    #expect(attribution.spans[1].parentID == attribution.spans[0].id)
    #expect(attribution.events.first?.parentSpanID == attribution.spans[1].id)
    #expect(attribution.spanSummaries.map(\.name) == ["IterationRoot", "ParseAST"])
  }

  @Test
  func zeroBaselineJSONRoundTrip() throws {
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
      baseline: BaselineDocument(cases: [baselineCase("Parser", "Tokenize", wallClock: [0])])
    )
    let report = try #require(document.suites.first?.cases.first)
    #expect(report.baselines.first?.percentageDelta == .infinity)
    #expect(report.verdict == .failed)

    let json = try JSONReportRenderer.render(document)
    #expect(json.contains("\"percentageDelta\" : null"))
    #expect(!json.contains("\"percentageDelta\" : 0"))
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: Data(json.utf8))
    #expect(decoded == document)
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

  private func wallClockSamples(_ values: [Double]) -> [Sample] {
    values.enumerated().map { Sample(iteration: $0.offset, values: [.wallClock: $0.element]) }
  }

  private func baselineCase(_ suiteName: String, _ caseName: String, wallClock: [Double])
    -> BaselineCase
  {
    BaselineCase(
      suiteName: suiteName,
      caseName: caseName,
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

  private func makeTimeline() -> Timeline {
    let clock = TickClock([10, 30, 31])
    let recorder = InMemoryRecorder(
      clock: {
        clock.next()
      },
      stackKey: { 1 }
    )
    let attributes: SpanAttributes = [
      TimelineCorrelationKeys.suite: "Parser",
      TimelineCorrelationKeys.case: "ParseDocument",
      TimelineCorrelationKeys.iteration: 1,
    ]
    let token = recorder.beginSpan("ParseAST", attributes: attributes)
    recorder.endSpan(token)
    recorder.recordEvent("CacheMiss", attributes: attributes)
    return recorder.snapshot()
  }

  private func makeNestedTimeline() -> Timeline {
    let clock = TickClock([10, 11, 12, 19, 20])
    let recorder = InMemoryRecorder(
      clock: {
        clock.next()
      },
      stackKey: { 1 }
    )
    let attributes: SpanAttributes = [
      TimelineCorrelationKeys.suite: "Parser",
      TimelineCorrelationKeys.case: "ParseDocument",
      TimelineCorrelationKeys.iteration: 1,
    ]
    let parent = recorder.beginSpan("IterationRoot", attributes: attributes)
    let child = recorder.beginSpan("ParseAST", attributes: .empty)
    recorder.recordEvent("CacheMiss", attributes: .empty)
    recorder.endSpan(child)
    recorder.endSpan(parent)
    return recorder.snapshot()
  }

  private func reportFixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: name, withExtension: nil)!
  }
}

private final class TickClock: @unchecked Sendable {
  private var ticks: [UInt64]

  init(_ ticks: [UInt64]) {
    self.ticks = ticks
  }

  func next() -> UInt64 {
    ticks.removeFirst()
  }
}

private struct ReportStepClock: BenchmarkClock {
  private let counter = ReportStepCounter()
  private let step: UInt64

  init(step: UInt64) {
    self.step = step
  }

  func now() -> BenchmarkInstant {
    counter.increment()
    return BenchmarkInstant(nanoseconds: UInt64(counter.value) * step)
  }
}

private final class ReportStepCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.withLock {
      storage
    }
  }

  func increment() {
    lock.withLock {
      storage += 1
    }
  }
}

extension RunMetadata {
  static func fixture() -> RunMetadata {
    RunMetadata(
      id: "run:test",
      swiftVersion: "6.3.1",
      packageIdentity: "swift-benchmark",
      gitCommit: "fixture",
      platform: "macOS",
      architecture: "arm64",
      osVersion: "15",
      generatedAt: "2026-05-11T00:00:00Z",
      buildConfiguration: "debug"
    )
  }
}
