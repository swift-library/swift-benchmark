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
  func stepIdentifiersKeepDistinctNamesDistinct() throws {
    let suites = ["Sort Array", "Sort-Array", "sort array"].map { name in
      BenchmarkSuite(name) {
        Benchmark("Case A") {}
        Benchmark("Case-A") {}
        Benchmark("case:a") {}
      }
    }

    let steps = try BenchmarkRunner.Plan(suites: suites).steps

    #expect(steps.count == 9)
    #expect(Set(steps.map(\.id)).count == 9)
    #expect(steps[2].id == "benchmark:Sort%20Array:case%3Aa")
  }

  @Test
  func argumentRowIdentifiersDoNotDependOnCollectionOrder() throws {
    func stepIDs<C: Collection & Sendable>(_ arguments: C) throws -> [String: String]
    where C.Element: Sendable {
      let suite = BenchmarkSuite("Rows") {
        Benchmark("Case", arguments: arguments) { value in blackHole(value) }
      }
      return Dictionary(
        uniqueKeysWithValues: try BenchmarkRunner.Plan(suites: [suite]).steps.map { step in
          (step.arguments.map(\.label).joined(), step.id)
        })
    }

    #expect(try stepIDs(["b", "a:c"]) == stepIDs(["a:c", "b"]))
    #expect(try stepIDs(["b", "a:c"])["a:c"] == "benchmark:Rows:Case:a%3Ac")
    let repeated = try BenchmarkRunner.Plan(suites: [
      BenchmarkSuite("Rows") {
        Benchmark("Case", arguments: ["x", "x"]) { value in blackHole(value) }
      }
    ]).steps
    #expect(repeated.map(\.id) == ["benchmark:Rows:Case:x", "benchmark:Rows:Case:x#2"])
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
    #expect(all.steps[0].id == "benchmark:TraitPlan:Runs")

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
