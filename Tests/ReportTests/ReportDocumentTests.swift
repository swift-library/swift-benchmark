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
      clock: StepClock(step: 11), cpuClock: nil, countsAllocations: false)

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
  func reportThisVersionCannotReadAsksToGenerateItAgain() throws {
    let earlierReport = Data(#"{"schemaVersion": 1, "suites": []}"#.utf8)

    let error = #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ReportDocument.self, from: earlierReport)
    }

    guard case .dataCorrupted(let context) = error else {
      Issue.record("Expected corrupted data, got \(String(describing: error))")
      return
    }
    #expect(context.debugDescription.contains("generate it again"))
    #expect(context.underlyingError != nil)
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
      profiles.first?["name"] as? String == "Parser.ParseDocument sample:Parser.ParseDocument.1")
  }
}
