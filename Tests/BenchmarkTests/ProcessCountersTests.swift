// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Testing

@Suite("Process Counters")
struct ProcessCountersTests {
  @Test
  func instructionsAreCountedPerCall() async throws {
    let loopIterations = 100_000
    func instructions(batch: Int) async throws -> Double? {
      let suite = BenchmarkSuite(
        "Counters",
        configuration: BenchmarkConfiguration(
          warmup: .iterations(1), iterations: .iterations(3), batching: .fixed(batch))
      ) {
        Benchmark("Loop") {
          blackHole(spin(loopIterations))
        }
      }
      let results = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)
      return median(values(of: .instructions, in: results))
    }

    guard let single = try await instructions(batch: 1),
      let batched = try await instructions(batch: 20)
    else {
      // The hardware counters are unavailable here, as in some virtual
      // machines and containers.
      return
    }

    // The loop body retires at least one instruction per iteration. A batch
    // reports per-call counts: undivided, the 20-call batch would read about
    // twenty times the single call. Other tests in this process add their
    // own instructions, so the comparison allows for that noise.
    #expect(single >= Double(loopIterations))
    #expect(batched >= Double(loopIterations))
    #expect(batched / single < 2)
  }

  @Test
  func operatingSystemEventsAreRecordedOnlyWhenCounted() async throws {
    let suite = BenchmarkSuite(
      "Events",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Work") {
        blackHole(spin(1_000))
      }
    }

    let counted = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)
    let uncounted = try await BenchmarkRunner(
      cpuClock: nil, countsProcessEvents: false, countsAllocations: false
    ).run(suite)

    #if canImport(Darwin) || os(Linux)
      #expect(!values(of: .contextSwitches, in: counted).isEmpty)
      #expect(!values(of: .pageFaults, in: counted).isEmpty)
    #endif
    #if canImport(Darwin)
      #expect(!values(of: .systemCalls, in: counted).isEmpty)
    #endif
    let uncountedMetrics = Set(uncounted.first?.measurement.samples.flatMap(\.values.keys) ?? [])
    #expect(uncountedMetrics == [.wallClock])
  }

  #if os(Linux)
    @Test
    func linuxLeavesOutInstructionsOfAsynchronousWorkloads() async throws {
      let suite = BenchmarkSuite(
        "Async",
        configuration: BenchmarkConfiguration(
          warmup: .none, iterations: .iterations(1), batching: .fixed(1))
      ) {
        Benchmark("Work") { () async in
          blackHole(spin(1_000))
        }
      }

      let results = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)

      #expect(values(of: .instructions, in: results).isEmpty)
    }
  #endif
}

private func values(of metric: Benchmark.Metric, in results: [BenchmarkResult]) -> [Double] {
  results.flatMap { $0.measurement.samples.compactMap { $0.value(for: metric) } }
}

private func median(_ values: [Double]) -> Double? {
  guard !values.isEmpty else {
    return nil
  }
  let sorted = values.sorted()
  return sorted[sorted.count / 2]
}

@inline(never)
private func spin(_ iterations: Int) -> Int {
  var value = 0
  for index in 0..<iterations {
    value = value &+ (index &* 31) ^ (value >> 3)
  }
  return value
}
