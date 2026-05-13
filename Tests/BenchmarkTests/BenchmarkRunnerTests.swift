import Benchmark
import Foundation
import Testing

@Suite("Benchmark Runner")
struct BenchmarkRunnerTests {
  @Test
  func runnerExecutesWarmupBeforeMeasuredIterations() async throws {
    let counter = Counter()
    let suite = BenchmarkSuite(
      "Runner",
      configuration: BenchmarkConfiguration(warmup: .iterations(2), iterations: .iterations(3))
    ) {
      Benchmark("Case") {
        counter.increment()
      }
    }
    let runner = BenchmarkRunner(clock: StepClock(step: 10))

    let results = try await runner.run(suite)

    #expect(counter.value == 5)
    #expect(results.count == 1)
    #expect(results[0].measurement.samples.count == 3)
    #expect(results[0].measurement.rows.count == 1)
    #expect(results[0].measurement.rows[0].size == nil)
    #expect(results[0].measurement.samples.map(\.durationNanoseconds) == [10, 10, 10])
  }

  @Test
  func runnerProducesOneMeasurementRowPerDimensionSize() async throws {
    let generated = Counter()
    let measured = Counter()
    let suite = BenchmarkSuite(
      "Runner",
      configuration: BenchmarkConfiguration(warmup: .iterations(1), iterations: .iterations(2))
    ) {
      Benchmark(
        "Dimensioned",
        dimension: Benchmark.Dimension(sizes: [10, 100]),
        input: { size in
          generated.increment()
          return size.rawValue
        }
      ) { value in
        measured.increment(by: value)
      }
    }

    let results = try await BenchmarkRunner(clock: StepClock(step: 5)).run(suite)
    let rows = try #require(results.first?.measurement.rows)

    #expect(generated.value == 2)
    #expect(measured.value == (10 * 3) + (100 * 3))
    #expect(rows.map(\.size?.rawValue) == [10, 100])
    #expect(rows.map { $0.samples.map(\.durationNanoseconds) } == [[5, 5], [5, 5]])
    #expect(results[0].measurement.samples.map(\.durationNanoseconds) == [5, 5, 5, 5])
  }

  @Test
  func planFiltersAndExpandsDimensionSteps() async throws {
    let suite = BenchmarkSuite(
      "Plan",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
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
    let results = try await BenchmarkRunner(clock: StepClock(step: 7)).run(plan)

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
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1)),
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
    let results = try await BenchmarkRunner(clock: StepClock(step: 1)).run(filtered)
    #expect(results.map(\.caseName) == ["Runs"])
    #expect(counter.value == 1)
  }

  @Test
  func eventStreamRecordsLifecycleAndJSONLines() async throws {
    let suite = BenchmarkSuite(
      "Events",
      configuration: BenchmarkConfiguration(warmup: .iterations(1), iterations: .iterations(1)),
      traits: [.tag("evented")]
    ) {
      Benchmark("Case") {}
    }
    let memory = Benchmark.Event.InMemoryRecorder()
    let jsonLines = Benchmark.Event.JSONLinesRecorder()

    _ = try await BenchmarkRunner(clock: StepClock(step: 3)).run(
      suite,
      eventRecorders: [memory, jsonLines]
    )

    let records = await memory.snapshot()
    #expect(records.map(\.sequence) == Array(records.indices))
    #expect(records.map(\.kind).contains(.planStarted))
    #expect(records.map(\.kind).contains(.caseStarted))
    #expect(records.map(\.kind).contains(.warmupStarted))
    #expect(records.map(\.kind).contains(.sampleRecorded))
    #expect(records.map(\.kind).contains(.planEnded))
    #expect(records.first { $0.kind == .sampleRecorded }?.context.durationNanoseconds == 3)
    #expect(records.first { $0.kind == .caseStarted }?.context.tags == ["evented"])

    let lines = await jsonLines.lines()
    #expect(lines.count == records.count)
    #expect(lines.first?.contains("\"kind\":\"planStarted\"") == true)
  }

  @Test
  func runnerPreservesThrownErrorsWithContext() async {
    enum DummyError: Error, Equatable {
      case boom
    }

    let suite = BenchmarkSuite(
      "Runner",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(2))
    ) {
      Benchmark("Throws") {
        throw DummyError.boom
      }
    }
    let runner = BenchmarkRunner(clock: StepClock(step: 1))

    do {
      _ = try await runner.run(suite)
      Issue.record("Expected runner to throw")
    } catch let error as BenchmarkRunnerError {
      #expect(String(describing: error).contains("Runner.Throws"))
      #expect(String(describing: error).contains("measurement"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func invalidConfigurationFailsBeforeExecutingCase() async {
    let counter = Counter()
    let suite = BenchmarkSuite(
      "Invalid",
      configuration: BenchmarkConfiguration(iterations: .iterations(0))
    ) {
      Benchmark("NeverRuns") {
        counter.increment()
      }
    }

    do {
      _ = try await BenchmarkRunner(clock: StepClock(step: 1)).run(suite)
      Issue.record("Expected invalid configuration to throw")
    } catch {
      #expect(counter.value == 0)
      #expect(String(describing: error).contains("configuration"))
    }
  }

  @Test
  func adaptivePolicyRunsUntilMinimumDurationOrMaximumIterations() async throws {
    let suite = BenchmarkSuite(
      "Adaptive",
      configuration: BenchmarkConfiguration(
        warmup: .none,
        iterations: .adaptive(
          minIterations: 1,
          maxIterations: 10,
          minDurationNanoseconds: 25
        )
      )
    ) {
      Benchmark("MinimumDuration") {}
    }

    let results = try await BenchmarkRunner(clock: StepClock(step: 10)).run(suite)

    #expect(results.first?.measurement.samples.map(\.durationNanoseconds) == [10, 10, 10])
  }

  @Test
  func adaptivePolicyHonorsMaximumDurationAndMinimumIterations() async throws {
    let suite = BenchmarkSuite(
      "Adaptive",
      configuration: BenchmarkConfiguration(
        warmup: .none,
        iterations: .adaptive(
          minIterations: 2,
          maxIterations: 10,
          maxDurationNanoseconds: 15
        )
      )
    ) {
      Benchmark("MaximumDuration") {}
    }

    let results = try await BenchmarkRunner(clock: StepClock(step: 10)).run(suite)

    #expect(results.first?.measurement.samples.map(\.durationNanoseconds) == [10, 10])
  }

  @Test
  func invalidAdaptivePolicyFailsBeforeExecutingCase() async {
    let counter = Counter()
    let suite = BenchmarkSuite(
      "InvalidAdaptive",
      configuration: BenchmarkConfiguration(
        warmup: .none,
        iterations: .adaptive(minIterations: 3, maxIterations: 2)
      )
    ) {
      Benchmark("NeverRuns") {
        counter.increment()
      }
    }

    do {
      _ = try await BenchmarkRunner(clock: StepClock(step: 1)).run(suite)
      Issue.record("Expected invalid adaptive configuration to throw")
    } catch {
      #expect(counter.value == 0)
      #expect(String(describing: error).contains("Adaptive maxIterations"))
    }
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.withLock {
      storage
    }
  }

  func increment(by amount: Int = 1) {
    lock.withLock {
      storage += amount
    }
  }
}

private struct StepClock: BenchmarkClock {
  private let counter: Counter
  private let step: UInt64

  init(step: UInt64) {
    self.counter = Counter()
    self.step = step
  }

  func now() -> BenchmarkInstant {
    counter.increment()
    return BenchmarkInstant(nanoseconds: UInt64(counter.value) * step)
  }
}
