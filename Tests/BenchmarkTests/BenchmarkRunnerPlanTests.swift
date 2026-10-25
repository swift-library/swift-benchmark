// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Testing

@Suite("Benchmark Runner Plan")
struct BenchmarkRunnerPlanTests {
  @Test
  func planFiltersAndExpandsDimensionSteps() async throws {
    let suite = BenchmarkSuite(
      "Plan",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Plain") {}
      Benchmark(
        "Dimensioned",
        dimension: Benchmark.Dimension(sizes: [10, 100]),
        input: { size in size.rawValue }
      ) { value in
        blackHole(value)
      }
    }

    let plan = try BenchmarkRunner.Plan(
      suites: [suite],
      filter: BenchmarkRunner.Plan.Filter(suiteName: "Plan", caseName: "Dimensioned")
    )
    let results = try await exactRunner(step: 7).run(plan)

    #expect(plan.steps.map(\.caseName) == ["Dimensioned", "Dimensioned"])
    #expect(plan.steps.map(\.size?.rawValue) == [10, 100])
    #expect(results.map(\.caseName) == ["Dimensioned"])
    #expect(results.first?.measurement.rows.map(\.size?.rawValue) == [10, 100])
  }

  @Test
  func planMergesTraitsTagsSkipsAndPlanningFailures() async throws {
    let counter = Counter()
    let suite = BenchmarkSuite(
      "TraitPlan",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1)),
      traits: [.tag("parser")]
    ) {
      Benchmark("Runs", traits: [.tag("fast")]) {
        counter.increment()
      }
      Benchmark("Skipped", traits: [.skip("not on this platform")]) {
        counter.increment(by: 10)
      }
      Benchmark(
        "Conflict",
        dimension: Benchmark.Dimension(sizes: [1]),
        traits: [.dimension(sizes: [2])],
        input: { size in size.rawValue }
      ) { value in
        blackHole(value)
      }
    }

    let all = try BenchmarkRunner.Plan(suites: [suite])
    #expect(all.steps.map(\.caseName) == ["Runs", "Skipped", "Conflict"])
    #expect(all.steps[0].tags == ["parser", "fast"])
    #expect(all.steps[0].id == "benchmark:traitplan:runs")

    guard case .skip(let reason) = all.steps[1].action else {
      Issue.record("Expected skip action")
      return
    }
    #expect(reason == "not on this platform")

    guard case .planningFailure(let issue) = all.steps[2].action else {
      Issue.record("Expected planning failure action")
      return
    }
    #expect(String(describing: issue).contains("conflicting Dimension"))

    let filtered = try BenchmarkRunner.Plan(
      suites: [suite],
      filter: BenchmarkRunner.Plan.Filter(casePattern: "Run*", tags: ["fast"])
    )
    let results = try await exactRunner(step: 1).run(filtered)
    #expect(results.map(\.caseName) == ["Runs"])
    #expect(counter.value == 1)
  }
}
