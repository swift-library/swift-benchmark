// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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
      configuration: BenchmarkConfiguration(
        warmup: .iterations(2), iterations: .iterations(3), batching: .fixed(1))
    ) {
      Benchmark("Case") {
        counter.increment()
      }
    }
    let runner = exactRunner(step: 10)

    let results = try await runner.run(suite)

    #expect(counter.value == 5)
    #expect(results.count == 1)
    #expect(results[0].measurement.samples.count == 3)
    #expect(results[0].measurement.rows.count == 1)
    #expect(results[0].measurement.rows[0].size == nil)
    #expect(results[0].measurement.samples.map { $0.value(for: .wallClock) } == [10, 10, 10])
  }

  @Test
  func runnerProducesOneMeasurementRowPerDimensionSize() async throws {
    let generated = Counter()
    let measured = Counter()
    let suite = BenchmarkSuite(
      "Runner",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(2), batching: .fixed(1))
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

    let results = try await exactRunner(step: 5).run(suite)
    let rows = try #require(results.first?.measurement.rows)
    let expectedMeasuredTotal: Int = (10 * 3) + (100 * 3)

    #expect(generated.value == 2)
    #expect(measured.value == expectedMeasuredTotal)
    #expect(rows.map(\.size?.rawValue) == [10, 100])
    #expect(
      rows.map { $0.samples.map { sample in sample.value(for: .wallClock) } } == [[5, 5], [5, 5]])
    #expect(results[0].measurement.samples.map { $0.value(for: .wallClock) } == [5, 5, 5, 5])
  }

  @Test
  func runnerProducesRowsAndCurvesForIntegerArguments() async throws {
    let measured = Counter()
    let suite = BenchmarkSuite(
      "Arguments",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Integer", arguments: [1, 2, 4]) { value in
        measured.increment(by: value)
      }
    }

    let results = try await exactRunner(step: 5).run(suite)
    let rows = try #require(results.first?.measurement.rows)
    let expectedMeasuredTotal: Int = (1 + 2 + 4) * 3

    #expect(measured.value == expectedMeasuredTotal)
    #expect(rows.map(\.size?.rawValue) == [1, 2, 4])
    #expect(rows.map { $0.arguments.map(\.label) } == [["1"], ["2"], ["4"]])
  }

  @Test
  func runnerProducesRowsWithoutCurvesForStringArguments() async throws {
    let suite = BenchmarkSuite(
      "Arguments",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Files", arguments: ["small.md", "large.md"]) { file in
        blackHole(file)
      }
    }

    let results = try await exactRunner(step: 5).run(suite)
    let rows = try #require(results.first?.measurement.rows)

    #expect(rows.map(\.size?.rawValue) == [nil, nil])
    #expect(rows.map { $0.arguments.map(\.label) } == [["small.md"], ["large.md"]])
  }

  @Test
  func runnerInfersScaleFromRawRepresentableIntegerArguments() async throws {
    enum Fixture: Int, Sendable {
      case small = 10
      case large = 100
    }

    let suite = BenchmarkSuite(
      "Arguments",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Raw", arguments: [Fixture.small, .large]) { fixture in
        blackHole(fixture)
      }
    }

    let rows = try await exactRunner(step: 5).run(suite)
      .first?.measurement.rows

    #expect(rows?.map(\.size?.rawValue) == [10, 100])
  }

  @Test
  func runnerSupportsCartesianAndZippedArguments() async throws {
    let cartesian = BenchmarkSuite(
      "Arguments",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Cartesian", arguments: [1, 2], ["a", "b"]) { number, string in
        blackHole((number, string))
      }
      Benchmark("Zipped", arguments: zip([1, 2], ["a", "b"])) { number, string in
        blackHole((number, string))
      }
    }

    let plan = try BenchmarkRunner.Plan(suites: [cartesian])

    #expect(plan.steps.filter { $0.caseName == "Cartesian" }.count == 4)
    #expect(plan.steps.filter { $0.caseName == "Zipped" }.count == 2)
  }

  @Test
  func eventStreamRecordsLifecycleAndJSONLines() async throws {
    let suite = BenchmarkSuite(
      "Events",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(1), batching: .fixed(1)),
      traits: [.tag("evented")]
    ) {
      Benchmark("Case") {}
    }
    let memory = Benchmark.Event.InMemoryRecorder()
    let jsonLines = Benchmark.Event.JSONLinesRecorder()

    _ = try await exactRunner(step: 3).run(
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
    let sampleContext = records.first { $0.kind == .sampleRecorded }?.context
    #expect(sampleContext?.values == ["wallClock": 3])
    #expect(sampleContext?.batchSize == 1)
    #expect(sampleContext?.metrics == [.wallClock])
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
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Throws") {
        throw DummyError.boom
      }
    }
    let runner = exactRunner(step: 1)

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
      configuration: BenchmarkConfiguration(iterations: .iterations(0), batching: .fixed(1))
    ) {
      Benchmark("NeverRuns") {
        counter.increment()
      }
    }

    do {
      _ = try await exactRunner(step: 1).run(suite)
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
        ),
        batching: .fixed(1)
      )
    ) {
      Benchmark("MinimumDuration") {}
    }

    let results = try await exactRunner(step: 10).run(suite)

    #expect(results.first?.measurement.samples.map { $0.value(for: .wallClock) } == [10, 10, 10])
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
        ),
        batching: .fixed(1)
      )
    ) {
      Benchmark("MaximumDuration") {}
    }

    let results = try await exactRunner(step: 10).run(suite)

    #expect(results.first?.measurement.samples.map { $0.value(for: .wallClock) } == [10, 10])
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
      _ = try await exactRunner(step: 1).run(suite)
      Issue.record("Expected invalid adaptive configuration to throw")
    } catch {
      #expect(counter.value == 0)
      #expect(String(describing: error).contains("Adaptive maxIterations"))
    }
  }
}
