// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Testing

@Suite("Benchmark Measurement")
struct BenchmarkMeasurementTests {
  @Test
  func automaticBatchingGrowsTheBatchToTheTargetAndReportsPerCallTime() async throws {
    let work = VirtualWork(nanosecondsPerCall: 100)
    let suite = BenchmarkSuite(
      "Batching",
      configuration: BenchmarkConfiguration(
        warmup: .none,
        iterations: .iterations(3),
        batching: .automatic(targetNanoseconds: 10_000)
      )
    ) {
      Benchmark("Short") {
        work.call()
      }
    }

    let results = try await BenchmarkRunner(
      clock: work.clock, cpuClock: nil, countsAllocations: false
    ).run(suite)
    let samples = try #require(results.first?.measurement.samples)

    #expect(samples.map(\.batchSize) == [100, 100, 100])
    #expect(samples.map { $0.value(for: .wallClock) } == [100, 100, 100])
  }

  @Test
  func automaticBatchingMeasuresSlowWorkloadsOneCallPerSample() async throws {
    let work = VirtualWork(nanosecondsPerCall: 50_000)
    let suite = BenchmarkSuite(
      "Batching",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1),
        iterations: .iterations(2),
        batching: .automatic(targetNanoseconds: 10_000)
      )
    ) {
      Benchmark("Long") {
        work.call()
      }
    }

    let results = try await BenchmarkRunner(
      clock: work.clock, cpuClock: nil, countsAllocations: false
    ).run(suite)

    #expect(work.calls == 3)
    #expect(results.first?.measurement.samples.map(\.batchSize) == [1, 1])
  }

  @Test
  func cpuTimeComesFromTheCPUClockPerCall() async throws {
    let suite = BenchmarkSuite(
      "CPU",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(4))
    ) {
      Benchmark("Case") {}
    }

    let results = try await BenchmarkRunner(
      clock: ContinuousBenchmarkClock(),
      cpuClock: FixedStepClock(step: 40),
      countsAllocations: false
    ).run(suite)

    #expect(results.first?.measurement.samples.map { $0.value(for: .cpuTime) } == [10, 10])
  }

  @Test
  func countingPassReportsSwiftHeapAllocationsAndReferenceCounting() async throws {
    let suite = BenchmarkSuite(
      "Counting",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(10))
    ) {
      Benchmark("ThreeNodes") {
        blackHole(makeList(count: 3))
      }
    }

    let results = try await BenchmarkRunner(cpuClock: nil).run(suite)
    let samples = try #require(results.first?.measurement.samples)
    let counting = try #require(samples.first { $0.value(for: .allocations) != nil })

    #expect(samples.count == 2)
    #expect(samples.first?.value(for: .allocations) == nil)
    #expect(counting.batchSize == 10)
    // The runtime hooks count every thread of the test process, so other
    // tests running at the same time can only add to these counts.
    #expect(try #require(counting.value(for: .allocations)) >= 3)
    #expect(try #require(counting.value(for: .allocatedBytes)) >= 3 * 24)
    #expect(try #require(counting.value(for: .releases)) >= 3)
    #expect(counting.value(for: .wallClock) == nil)
  }

  @Test
  func recordedCustomMetricsAreSummedAndDividedByTheBatch() async throws {
    let bytesWritten = Benchmark.Metric(name: "bytesWritten", unit: .bytes)
    let suite = BenchmarkSuite(
      "Custom",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(2), batching: .fixed(4))
    ) {
      Benchmark("Writes") {
        Benchmark.record(512, for: bytesWritten)
      }
    }

    let results = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)

    #expect(results.first?.measurement.samples.map { $0.value(for: bytesWritten) } == [512, 512])
  }

  @Test
  func peakMemoryIsRecordedOnlyWhenTheRunnerOwnsTheProcess() async throws {
    let suite = BenchmarkSuite(
      "Peak",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Case") {}
    }

    let shared = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)
    let owned = try await BenchmarkRunner(
      cpuClock: nil, countsAllocations: false, recordsPeakMemory: true
    ).run(suite)

    #expect(
      shared.first?.measurement.samples.contains { $0.value(for: .peakMemory) != nil } == false)
    #if canImport(Darwin) || os(Linux)
      let peak = owned.first?.measurement.samples.compactMap { $0.value(for: .peakMemory) }
      #expect(peak?.count == 1)
      #expect((peak?.first ?? 0) > 0)
    #endif
  }

  @Test
  func invalidBatchSizeFailsBeforeExecutingCase() async {
    let work = VirtualWork(nanosecondsPerCall: 1)
    let suite = BenchmarkSuite(
      "Invalid",
      configuration: BenchmarkConfiguration(batching: .fixed(0))
    ) {
      Benchmark("NeverRuns") {
        work.call()
      }
    }

    await #expect(throws: BenchmarkRunnerError.self) {
      try await BenchmarkRunner(clock: work.clock).run(suite)
    }
    #expect(work.calls == 0)
  }
}

private final class Node {
  let next: Node?

  init(next: Node?) {
    self.next = next
  }
}

@inline(never)
private func makeList(count: Int) -> Node? {
  var head: Node?
  for _ in 0..<count {
    head = Node(next: head)
  }
  return head
}

/// A workload whose calls advance a virtual clock by a fixed cost.
private final class VirtualWork: @unchecked Sendable {
  private let lock = NSLock()
  private var elapsed: UInt64 = 0
  private var callCount = 0
  private let nanosecondsPerCall: UInt64

  init(nanosecondsPerCall: UInt64) {
    self.nanosecondsPerCall = nanosecondsPerCall
  }

  var calls: Int {
    lock.withLock { callCount }
  }

  var clock: VirtualClock {
    VirtualClock(work: self)
  }

  func call() {
    lock.withLock {
      elapsed += nanosecondsPerCall
      callCount += 1
    }
  }

  fileprivate func now() -> UInt64 {
    lock.withLock { elapsed }
  }
}

private struct VirtualClock: BenchmarkClock {
  let work: VirtualWork

  func now() -> BenchmarkInstant {
    BenchmarkInstant(nanoseconds: work.now())
  }
}

/// A clock that advances by `step` on every read.
private final class FixedStepClock: BenchmarkClock, @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 0
  private let step: UInt64

  init(step: UInt64) {
    self.step = step
  }

  func now() -> BenchmarkInstant {
    lock.withLock {
      value += step
      return BenchmarkInstant(nanoseconds: value)
    }
  }
}
