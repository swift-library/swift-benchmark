// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Testing

@Suite("Measurement Precision")
struct MeasurementPrecisionTests {
  @Test
  func wallClockMatchesTheTimeAWorkloadSpends() async throws {
    let spun = SpinLog()
    let suite = BenchmarkSuite(
      "Precision",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(10), batching: .fixed(1))
    ) {
      Benchmark("Spin") {
        spun.append(spin(for: .milliseconds(1)))
      }
    }

    let results = try await BenchmarkRunner(countsAllocations: false).run(suite)
    let wallClock = try #require(
      results.first?.measurement.samples.compactMap {
        $0.value(for: .wallClock)
      })
    let pairs = Array(zip(wallClock, spun.values.dropFirst()))

    #expect(pairs.count == 10)
    // Each sample's window encloses the time the workload saw itself spend.
    #expect(pairs.allSatisfy { measured, spent in measured >= spent })
    // One call the scheduler left alone shows what the runner adds around it.
    #expect((pairs.map { measured, spent in measured - spent }.min() ?? .infinity) < 50_000)
  }

  @Test
  func automaticBatchingTimesSubMicrosecondWorkloadsOverTheTargetDuration() async throws {
    let target: UInt64 = 200_000
    let suite = BenchmarkSuite(
      "Precision",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1),
        iterations: .iterations(5),
        batching: .automatic(targetNanoseconds: target)
      )
    ) {
      Benchmark("Increment") {
        var value = 0
        value &+= 1
        blackHole(value)
      }
    }

    let results = try await BenchmarkRunner(countsAllocations: false).run(suite)
    let samples = try #require(
      results.first?.measurement.samples.filter {
        $0.value(for: .wallClock) != nil
      })
    let perCall = samples.compactMap { $0.value(for: .wallClock) }

    #expect(samples.count == 5)
    #expect(samples.allSatisfy { $0.batchSize > 1 })
    #expect(median(perCall) < 1_000)
  }
}

/// Busy-waits for `duration` of wall-clock time and returns the nanoseconds
/// it spent, as the runner's clock counts them.
private func spin(for duration: Duration) -> Double {
  let clock = ContinuousClock()
  let start = clock.now
  let deadline = start.advanced(by: duration)
  var now = start
  while now < deadline {
    now = clock.now
  }
  let spent = start.duration(to: now).components
  return Double(spent.seconds) * 1e9 + Double(spent.attoseconds) / 1e9
}

private final class SpinLog: @unchecked Sendable {
  private let lock = NSLock()
  private var spent: [Double] = []

  var values: [Double] {
    lock.withLock { spent }
  }

  func append(_ nanoseconds: Double) {
    lock.withLock { spent.append(nanoseconds) }
  }
}

private func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  let middle = sorted.count / 2
  return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}
