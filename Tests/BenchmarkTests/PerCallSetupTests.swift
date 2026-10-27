// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Testing

@Suite("Per-Call Setup")
struct PerCallSetupTests {
  @Test
  func everyCallTakesAFreshInput() async throws {
    let setups = Tally()
    let unsortedInputs = Tally()
    let configuration = BenchmarkConfiguration(
      warmup: .iterations(1), iterations: .iterations(2), batching: .fixed(4))
    let suite = BenchmarkSuite("Setup", configuration: configuration) {
      Benchmark(
        "Sort",
        setup: { () -> [Int] in
          setups.add()
          return [3, 1, 2]
        }
      ) { values in
        if values != [1, 2, 3] {
          unsortedInputs.add()
        }
        values.sort()
      }
      Benchmark(
        "Sort asynchronously",
        setup: { () async -> [Int] in
          setups.add()
          return [3, 1, 2]
        }
      ) { (values: inout [Int]) async in
        if values != [1, 2, 3] {
          unsortedInputs.add()
        }
        values.sort()
      }
    }

    _ = try await BenchmarkRunner(cpuClock: nil, countsProcessEvents: false).run(suite)

    // Per case: one warmup call, two timed batches of four, and the counting
    // pass's batch of four.
    #expect(setups.value == 2 * (1 + 2 * 4 + 4))
    #expect(unsortedInputs.value == setups.value)
  }

  @Test
  func setupIsNotTimed() async throws {
    let configuration = BenchmarkConfiguration(
      warmup: .none, iterations: .iterations(3), batching: .fixed(5))
    let suite = BenchmarkSuite("Setup", configuration: configuration) {
      Benchmark(
        "Slow setup",
        setup: { () -> SetupProbe in
          Thread.sleep(forTimeInterval: 0.002)
          return SetupProbe()
        }
      ) { probe in
        probe.value += 1
      }
    }

    let results = try await BenchmarkRunner(cpuClock: nil, countsProcessEvents: false).run(suite)
    let measurement = try #require(results.first?.measurement)
    let wallClock = measurement.samples.compactMap { $0.value(for: .wallClock) }

    // Each setup sleeps 2 ms; the calls themselves take far less.
    #expect(wallClock.count == 3)
    #expect(wallClock.allSatisfy { $0 < 1_000_000 })
  }

  @Test
  func valuesSetupRecordsAreNotTheWorkloads() async throws {
    let parsed = Benchmark.Metric(name: "parsedItems", unit: .count)
    let suite = BenchmarkSuite(
      "Setup",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(3))
    ) {
      Benchmark(
        "Recording setup",
        setup: { () -> Int in
          Benchmark.record(100, for: parsed)
          return 1
        }
      ) { value in
        Benchmark.record(Double(value), for: parsed)
      }
    }

    let results = try await BenchmarkRunner(
      cpuClock: nil, countsProcessEvents: false, countsAllocations: false
    ).run(suite)
    let values = results.first?.measurement.samples.compactMap { $0.value(for: parsed) }

    #expect(values == [1, 1])
  }

  @Test
  func setupFailuresFailTheCase() async throws {
    let suite = BenchmarkSuite(
      "Setup",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Failing setup", setup: { () throws -> Int in throw SetupFailure() }) { _ in }
    }

    await #expect(throws: BenchmarkRunnerError.self) {
      try await BenchmarkRunner(cpuClock: nil, countsProcessEvents: false).run(suite)
    }
  }

  @Test
  func macroDeclaredSetupMakesInputsForEachSize() async throws {
    let results = try await BenchmarkRunner(cpuClock: nil, countsProcessEvents: false)
      .run(SetupMacroBenchmarks.__benchmarkSuites)

    #expect(results.map(\.caseName) == ["Sort", "Sort sized"])
    #expect(results.last?.measurement.rows.map(\.size) == [Benchmark.Scale(4), Benchmark.Scale(8)])
    #expect(results.allSatisfy { !$0.measurement.samples.isEmpty })
  }
}

@BenchmarkSuite(
  "Setup Macro",
  .configuration(
    BenchmarkConfiguration(warmup: .none, iterations: .iterations(1), batching: .fixed(2)))
)
struct SetupMacroBenchmarks {
  @Benchmark("Sort", setup: Self.threeReversed)
  func sort(_ values: inout [Int]) {
    precondition(values == [3, 2, 1])
    values.sort()
  }

  @Benchmark("Sort sized", .dimension(sizes: [4, 8]), setup: Self.reversed)
  static func sortSized(values: inout [Int]) {
    precondition(values.first == values.count)
    values.sort()
  }

  static func threeReversed() -> [Int] {
    [3, 2, 1]
  }

  static func reversed(_ size: Benchmark.Scale) -> [Int] {
    Array((1...size.rawValue).reversed())
  }
}

/// A count that `@Sendable` closures can share.
private final class Tally: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.withLock { count }
  }

  func add() {
    lock.withLock { count += 1 }
  }
}

private final class SetupProbe {
  var value = 0
}

private struct SetupFailure: Error {}
