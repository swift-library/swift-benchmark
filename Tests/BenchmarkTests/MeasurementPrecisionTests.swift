// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Testing

@Suite("Measurement Precision")
struct MeasurementPrecisionTests {
  @Test
  func wallClockMatchesTheTimeAWorkloadSpends() async throws {
    let suite = BenchmarkSuite(
      "Precision",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(10), batching: .fixed(1))
    ) {
      Benchmark("Spin") {
        spin(for: .milliseconds(1))
      }
    }

    let results = try await BenchmarkRunner(countsAllocations: false).run(suite)
    let wallClock = try #require(
      results.first?.measurement.samples.compactMap {
        $0.value(for: .wallClock)
      })

    #expect(wallClock.count == 10)
    #expect((1_000_000...1_200_000).contains(median(wallClock)))
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
    // Each sample spans enough calls that clock resolution is a negligible
    // part of the reported per-call time.
    #expect(
      samples.allSatisfy { sample in
        Double(sample.batchSize) * (sample.value(for: .wallClock) ?? 0) >= Double(target) / 2
      })
    #expect(median(perCall) < 1_000)
  }
}

/// Busy-waits for `duration` of wall-clock time.
private func spin(for duration: Duration) {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: duration)
  while clock.now < deadline {}
}

private func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  let middle = sorted.count / 2
  return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}
