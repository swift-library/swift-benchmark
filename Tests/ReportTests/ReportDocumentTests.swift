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
  func reportDocumentCorrelatesBenchmarkBaselineDiagnosticsAndTimeline() throws {
    let result = BenchmarkResult(
      suiteName: "Parser",
      caseName: "ParseDocument",
      configuration: BenchmarkConfiguration(warmup: .iterations(1), iterations: .iterations(2)),
      tags: ["parser", "critical"],
      measurement: Measurement(samples: [
        Sample(iteration: 0, durationNanoseconds: 1_000),
        Sample(iteration: 1, durationNanoseconds: 3_000),
      ])
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
    let caseID = ReportID(rawValue: "case:parser.parsedocument")
    let scope = ReportScope(runID: metadata.id, suiteID: "suite:parser", caseID: caseID)
    let diagnostic = DiagnosticMetric(
      id: "metric:memory",
      scope: scope,
      name: "memory.peak",
      state: .unavailable("memory metrics are unavailable on this platform")
    )
    let baseline = BaselineDocument(cases: [
      BaselineCase(suiteName: "Parser", caseName: "ParseDocument", meanNanoseconds: 1_000)
    ])

    let document = ReportDocument(
      metadata: metadata,
      results: [result],
      baseline: baseline,
      threshold: .relativePercentage(50),
      attributions: [attribution],
      diagnostics: [diagnostic]
    )

    let report = try #require(document.suites.first?.cases.first)
    #expect(document.summary.verdict == .failed)
    #expect(report.tags == ["parser", "critical"])
    #expect(report.samples.map(\.durationNanoseconds) == [1_000, 3_000])
    #expect(report.baseline?.absoluteDeltaNanoseconds == 1_000)
    #expect(report.baseline?.percentageDelta == 100)
    #expect(report.verdict == .failed)
    #expect(report.attribution?.spans.map(\.name) == ["ParseAST"])
    #expect(report.attribution?.events.map(\.name) == ["CacheMiss"])
    #expect(report.diagnostics.first?.state.kind == .unavailable)
    #expect(report.diagnostics.first?.state.value == nil)
  }

  @Test
  func jsonMarkdownAndConsoleRenderTheSameReportDocument() throws {
    let document = ReportDocument(
      metadata: .fixture(),
      results: [
        BenchmarkResult(
          suiteName: "Parser",
          caseName: "Tokenize",
          configuration: .default,
          measurement: Measurement(samples: [Sample(iteration: 0, durationNanoseconds: 2_000)])
        )
      ]
    )

    let json = try JSONReportRenderer.render(document)
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: Data(json.utf8))
    let markdown = MarkdownReportRenderer.render(document)
    let console = ConsoleReportRenderer.render(document)

    #expect(decoded == document)
    #expect(markdown.contains("Tokenize"))
    #expect(markdown.contains("2.000 us"))
    #expect(console.contains("Tokenize: mean 2.000 us"))
  }

  @Test
  func reportRecorderBuildsReportDocumentFromBenchmarkEventStream() async throws {
    let suite = BenchmarkSuite(
      "Events",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(2)),
      traits: [.tag("event-report")]
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let recorder = ReportRecorder()
    let runner = BenchmarkRunner(clock: ReportStepClock(step: 11))

    let results = try await runner.run(suite, eventRecorders: [recorder])
    let metadata = RunMetadata.fixture()
    let direct = ReportDocument(metadata: metadata, results: results)
    let eventBuilt = await recorder.document(metadata: metadata)
    let directReport = try #require(direct.suites.first?.cases.first)
    let eventReport = try #require(eventBuilt.suites.first?.cases.first)

    #expect(eventReport.name == directReport.name)
    #expect(eventReport.tags == ["event-report"])
    #expect(eventReport.samples.map(\.durationNanoseconds) == [11, 11])
    #expect(
      eventReport.samples.map(\.durationNanoseconds)
        == directReport.samples.map(\.durationNanoseconds))
    #expect(eventReport.configuration == directReport.configuration)
    #expect(eventReport.sourceLocation == directReport.sourceLocation)
  }

  @Test
  func jsonSchemaFixtureRoundTripsAndExposesVerdictCauses() throws {
    let fixture = try Data(contentsOf: reportFixtureURL("report-v2.json"))
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: fixture)
    let encoded = try JSONReportRenderer.render(decoded)
    let roundTripped = try JSONDecoder().decode(ReportDocument.self, from: Data(encoded.utf8))
    let report = try #require(roundTripped.suites.first?.cases.first)

    #expect(roundTripped == decoded)
    #expect(roundTripped.schemaVersion == ReportDocument.currentSchemaVersion)
    #expect(roundTripped.summary.verdict == .failed)
    #expect(report.tags == [])
    #expect(report.verdictCauses.map(\.kind) == [.budgetExceeded, .diagnosticFailed])
    #expect(report.sourceLocation?.line == 42)
    #expect(report.samples.map(\.durationNanoseconds) == [1_000, 2_000])
  }

  @Test
  func baselineAndBudgetSelectorsPreserveTypedVerdictCauses() throws {
    let result = BenchmarkResult(
      suiteName: "Parser",
      caseName: "ParseDocument",
      sourceLocation: BenchmarkSourceLocation(
        fileID: "ParserBenchmarks/ParserBenchmarks.swift",
        filePath: "/tmp/ParserBenchmarks.swift",
        line: 42,
        column: 5
      ),
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(3)),
      measurement: Measurement(samples: [
        Sample(iteration: 0, durationNanoseconds: 1_000),
        Sample(iteration: 1, durationNanoseconds: 2_000),
        Sample(iteration: 2, durationNanoseconds: 3_000),
      ])
    )
    let baseline = BaselineDocument(cases: [
      BaselineCase(
        suiteName: "Parser",
        caseName: "ParseDocument",
        meanNanoseconds: 2_000,
        metrics: Report.Measurement.Metrics(
          count: 3,
          min: 1_000,
          max: 2_000,
          mean: 1_800,
          median: 1_800,
          standardDeviation: 0,
          p90: 1_800,
          p95: 1_800,
          p99: 1_800
        )
      )
    ])

    let document = ReportDocument(
      metadata: .fixture(),
      results: [result],
      baseline: baseline,
      baselineMetric: .p95,
      threshold: .absoluteNanoseconds(1_000),
      budgets: [
        BudgetPolicy(metric: .mean, limitNanoseconds: 2_500),
        BudgetPolicy(metric: .p95, limitNanoseconds: 2_500),
      ]
    )
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.baseline?.metric == .p95)
    #expect(report.baseline?.currentValueNanoseconds == 2_900)
    #expect(report.baseline?.baselineValueNanoseconds == 1_800)
    #expect(report.baseline?.verdict == .failed)
    #expect(report.budgets.map(\.verdict) == [.passed, .failed])
    #expect(report.verdict == .failed)
    #expect(report.verdictCauses.map(\.kind) == [.baselineRegression, .budgetExceeded])
    #expect(report.verdictCauses.map(\.metric) == [.p95, .p95])
    #expect(document.summary.failedRegressionCount == 1)
    #expect(document.summary.failedBudgetCount == 1)
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
          measurement: Measurement(samples: [Sample(iteration: 0, durationNanoseconds: 2_000)])
        )
      ]
    )
    let baseline = BaselineDocument(cases: [
      BaselineCase(suiteName: "Parser", caseName: "Tokenize", meanNanoseconds: 1_000)
    ])
    let compared = original.comparing(
      baseline: baseline,
      threshold: .relativePercentage(10),
      budgets: [BudgetPolicy(metric: .mean, limitNanoseconds: 1_500)]
    )
    let report = try #require(compared.suites.first?.cases.first)

    #expect(report.samples.map(\.durationNanoseconds) == [2_000])
    #expect(report.baseline?.verdict == .failed)
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
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1)),
      measurement: Measurement(samples: [Sample(iteration: 1, durationNanoseconds: 20)])
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
          measurement: Measurement(samples: [Sample(iteration: 0, durationNanoseconds: 2_000)])
        )
      ],
      baseline: BaselineDocument(cases: [
        BaselineCase(suiteName: "Parser", caseName: "Tokenize", meanNanoseconds: 0)
      ]),
      threshold: .relativePercentage(10)
    )
    let report = try #require(document.suites.first?.cases.first)
    #expect(report.baseline?.percentageDelta == .infinity)
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
      currentMeanNanoseconds: 1_100,
      baselineMeanNanoseconds: 1_000,
      threshold: .absoluteNanoseconds(100)
    )

    #expect(comparison.verdict == .passed)
    #expect(comparison.absoluteDeltaNanoseconds == 100)
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
