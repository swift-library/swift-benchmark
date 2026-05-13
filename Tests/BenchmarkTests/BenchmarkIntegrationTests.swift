import Benchmark
import Foundation
import Testing

@BenchmarkSuite("Macro")
struct MacroDiscoveredBenchmarks {
  @Benchmark("Discovered")
  func discovered() {
    blackHole(1)
  }
}

@BenchmarkSuite("Macro Traits", .tag("suite-tag"))
struct MacroTraitDiscoveredBenchmarks {
  @Benchmark("Tagged", .tag("case-tag"))
  static func tagged() {
    blackHole(1)
  }
}

@BenchmarkSuite("Macro Dimension")
struct MacroDimensionDiscoveredBenchmarks {
  @Benchmark("Sized", .dimension(sizes: [3, 5]))
  func sized(size: Benchmark.Dimension.Size) {
    blackHole(size.rawValue)
  }
}

@Suite("Benchmark Integration")
struct BenchmarkIntegrationTests {
  @Test
  func runnerReturnsStructuredResults() async throws {
    let suite = BenchmarkSuite(
      "Integration",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
    ) {
      Benchmark("ReturnsValue") {
        "result"
      }
    }

    let results = try await BenchmarkRunner(clock: FixedClock()).run(suite)

    #expect(results.count == 1)
    #expect(results[0].suiteName == "Integration")
    #expect(results[0].caseName == "ReturnsValue")
    #expect(results[0].measurement.samples.count == 1)
    #expect(results[0].measurement.rows.count == 1)
  }

  @Test
  func macroDiscoveryMaterializesRunnerPlan() async throws {
    let discovery = BenchmarkDiscovery([MacroDiscoveredBenchmarks.self])
    let plan = try discovery.plan()
    let results = try await BenchmarkRunner(clock: FixedClock()).run(plan)

    #expect(discovery.suites.map(\.name) == ["Macro"])
    #expect(plan.steps.map(\.caseName) == ["Discovered"])
    #expect(results.map(\.caseName) == ["Discovered"])
    #expect(results.first?.measurement.rows.count == 1)
  }

  @Test
  func macroDiscoveryPreservesTraitTagsInRunnerPlan() throws {
    let discovery = BenchmarkDiscovery([MacroTraitDiscoveredBenchmarks.self])
    let plan = try discovery.plan(
      filter: BenchmarkRunner.Plan.Filter(tags: ["suite-tag", "case-tag"])
    )

    #expect(plan.steps.map(\.caseName) == ["Tagged"])
    #expect(plan.steps.first?.tags == ["suite-tag", "case-tag"])
  }

  @Test
  func macroDiscoveryLowersDimensionParameterIntoRows() async throws {
    let discovery = BenchmarkDiscovery([MacroDimensionDiscoveredBenchmarks.self])
    let plan = try discovery.plan()
    let results = try await BenchmarkRunner(clock: StepClock(step: 2)).run(plan)

    #expect(plan.steps.map(\.size?.rawValue) == [3, 5])
    #expect(results.first?.measurement.rows.map(\.size?.rawValue) == [3, 5])
    #expect(results.first?.measurement.rows.map { $0.samples.count } == [10, 10])
  }
}

private struct FixedClock: BenchmarkClock {
  func now() -> BenchmarkInstant {
    BenchmarkInstant(nanoseconds: 1)
  }
}

private struct StepClock: BenchmarkClock {
  private let counter = StepCounter()
  private let step: UInt64

  init(step: UInt64) {
    self.step = step
  }

  func now() -> BenchmarkInstant {
    BenchmarkInstant(nanoseconds: UInt64(counter.next()) * step)
  }
}

private final class StepCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      defer {
        value += 1
      }
      return value
    }
  }
}
