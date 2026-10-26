// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Report
import Testing

@Suite("Timeline Correlation")
struct TimelineCorrelationTests {
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
  func eachArgumentRowsIterationsAreAttributedToItsOwnSamples() async throws {
    let suite = BenchmarkSuite(
      "Rows",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Parse", arguments: ["small", "large"]) { name in blackHole(name) }
    }

    let document = try await BenchmarkCommand(
      runner: BenchmarkRunner(clock: StepClock(step: 100), cpuClock: nil, countsAllocations: false)
    )
    .report(
      plan: BenchmarkRunner.Plan(suites: [suite]),
      metadata: .fixture(),
      timelineCapture: .benchmarkIterations
    )
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.attributions.count == 4)
    #expect(report.attributions.allSatisfy { $0.spans.map(\.name) == ["BenchmarkIteration"] })
    #expect(
      Set(report.attributions.compactMap(\.scope.sampleID)) == Set(report.samples.map(\.id)))
  }
}
