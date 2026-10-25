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
      cpuClock: StepClock(step: 40),
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
    #expect(samples.first?.value(for: .allocations) == nil)
    guard let counting = samples.first(where: { $0.value(for: .allocations) != nil }) else {
      // A runtime without the instrumentation hooks leaves the counts out.
      #if canImport(Darwin)
        Issue.record("The Swift runtime on Darwin provides the instrumentation hooks.")
      #endif
      return
    }

    #expect(samples.count == 2)
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
  func peakMemoryIsTheGrowthAboveTheStepsStartingFootprint() async throws {
    let allocationBytes = 256 << 20
    let suite = BenchmarkSuite(
      "Peak",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Allocates") {
        var buffer = [UInt8](repeating: 1, count: allocationBytes)
        buffer[allocationBytes / 2] = 2
        blackHole(buffer)
      }
    }

    // The allocator can keep freed memory in the process footprint, so the
    // measured run must make the process's first allocation of this size.
    let owned = try await BenchmarkRunner(
      cpuClock: nil, countsAllocations: false, recordsPeakMemory: true
    ).run(suite)
    let shared = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)

    #expect(
      shared.first?.measurement.samples.contains { $0.value(for: .peakMemory) != nil } == false)
    #if canImport(Darwin) || os(Linux)
      let peak = owned.first?.measurement.samples.compactMap { $0.value(for: .peakMemory) }
      #expect(peak?.count == 1)
      #expect((peak?.first ?? 0) >= Double(allocationBytes / 2))
    #endif
  }

  @Test
  func cpuAndWallClocksAreReadAroundTheSameCalls() async throws {
    let log = ReadLog()
    let suite = BenchmarkSuite(
      "Window",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(2))
    ) {
      Benchmark("Case") {
        log.append("call")
      }
    }

    _ = try await BenchmarkRunner(
      clock: LoggingClock(name: "wall", log: log),
      cpuClock: LoggingClock(name: "cpu", log: log),
      countsAllocations: false
    ).run(suite)

    #expect(log.entries == ["cpu", "wall", "call", "call", "wall", "cpu"])
  }

  @Test
  func recordedValuesUseTheFirstDescriptorAndSkipBuiltInNames() async throws {
    let first = Benchmark.Metric(name: "work", unit: .count)
    let conflicting = Benchmark.Metric(name: "work", unit: .bytes)
    let suite = BenchmarkSuite(
      "Descriptors",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Case") {
        Benchmark.record(1, for: first)
        Benchmark.record(2, for: conflicting)
        Benchmark.record(1_000_000, for: Benchmark.Metric(name: "wallClock", unit: .count))
      }
    }
    let events = Benchmark.Event.InMemoryRecorder()

    let results = try await BenchmarkRunner(
      clock: VirtualWork(nanosecondsPerCall: 0).clock, cpuClock: nil, countsAllocations: false
    ).run(suite, eventRecorders: [events])
    let sample = try #require(results.first?.measurement.samples.first)

    #expect(first == conflicting)
    #expect(sample.value(for: first) == 3)
    #expect(sample.value(for: .wallClock) == 0)
    let context = await events.snapshot().first { $0.kind == .sampleRecorded }?.context
    #expect(context?.values["work"] == 3)
  }

  @Test
  func concurrentRunnersMeasureOneStepAtATime() async throws {
    let tracker = ConcurrencyTracker()
    func suite(_ name: String) -> BenchmarkSuite {
      BenchmarkSuite(
        name,
        configuration: BenchmarkConfiguration(
          warmup: .iterations(1), iterations: .iterations(3), batching: .fixed(5))
      ) {
        Benchmark("Case") {
          tracker.enter()
          blackHole((0..<200).reduce(0, +))
          tracker.leave()
        }
      }
    }

    async let first = BenchmarkRunner(cpuClock: nil).run(suite("First"))
    async let second = BenchmarkRunner(cpuClock: nil).run(suite("Second"))
    _ = try await (first, second)

    #expect(tracker.maximum == 1)
  }

  @Test
  func calibrationClampsLargeTargetsToTheMaximumBatch() async throws {
    let work = VirtualWork(nanosecondsPerCall: 1)
    let suite = BenchmarkSuite(
      "Clamp",
      configuration: BenchmarkConfiguration(
        warmup: .none,
        iterations: .iterations(1),
        batching: .automatic(targetNanoseconds: .max, maxBatchSize: 50)
      )
    ) {
      Benchmark("Case") {
        work.call()
      }
    }

    let results = try await BenchmarkRunner(
      clock: work.clock, cpuClock: nil, countsAllocations: false
    ).run(suite)

    #expect(results.first?.measurement.samples.map(\.batchSize) == [50])
  }

  @Test
  func adaptiveIterationsCountTheWholeBatchTowardDurationLimits() async throws {
    func run(_ iterations: IterationPolicy) async throws -> [Sample] {
      let work = VirtualWork(nanosecondsPerCall: 100)
      let suite = BenchmarkSuite(
        "Adaptive",
        configuration: BenchmarkConfiguration(
          warmup: .none, iterations: iterations, batching: .fixed(10))
      ) {
        Benchmark("Case") {
          work.call()
        }
      }
      let results = try await BenchmarkRunner(
        clock: work.clock, cpuClock: nil, countsAllocations: false
      ).run(suite)
      return results.first?.measurement.samples ?? []
    }

    let minimum = try await run(
      .adaptive(minIterations: 1, maxIterations: 10, minDurationNanoseconds: 2_500))
    let maximum = try await run(
      .adaptive(minIterations: 2, maxIterations: 10, maxDurationNanoseconds: 1_500))

    #expect(minimum.count == 3)
    #expect(minimum.map { $0.value(for: .wallClock) } == [100, 100, 100])
    #expect(maximum.count == 2)
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

/// An ordered log that clocks and workloads append to.
private final class ReadLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  var entries: [String] {
    lock.withLock { storage }
  }

  func append(_ entry: String) {
    lock.withLock { storage.append(entry) }
  }
}

private struct LoggingClock: BenchmarkClock {
  let name: String
  let log: ReadLog

  func now() -> BenchmarkInstant {
    log.append(name)
    return BenchmarkInstant(nanoseconds: 0)
  }
}

/// Records the most workloads that ran at the same time.
private final class ConcurrencyTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var active = 0
  private var peak = 0

  var maximum: Int {
    lock.withLock { peak }
  }

  func enter() {
    lock.withLock {
      active += 1
      peak = max(peak, active)
    }
  }

  func leave() {
    lock.withLock { active -= 1 }
  }
}
