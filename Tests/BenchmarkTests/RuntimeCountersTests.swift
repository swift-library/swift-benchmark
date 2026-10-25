// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Synchronization
import Testing

@testable import Benchmark

@Suite("Runtime Counters")
struct RuntimeCountersTests {
  @Test
  func stepsAreTimedWithTheRuntimesSwitchOffAfterCountingRaces() async throws {
    guard RuntimeCounters.callsThroughHookSlots != nil else {
      return
    }
    let allocator = AllocatingThread()
    // Counting while another thread allocates can leave the switch on.
    try await MeasurementGate.shared.withExclusiveAccess {
      for _ in 0..<2_000 {
        _ = try await RuntimeCounters.counting {}
      }
    }
    let observed = Observations()
    let suite = BenchmarkSuite(
      "Switch",
      configuration: BenchmarkConfiguration(
        warmup: .iterations(1), iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Observe") {
        observed.append(RuntimeCounters.callsThroughHookSlots)
      }
    }

    _ = try await BenchmarkRunner(cpuClock: nil, countsAllocations: false).run(suite)
    allocator.stop()

    // A test process starts with the switch off.
    #expect(observed.values == [false, false, false])
  }
}

/// A thread that allocates Swift objects from creation until it is stopped.
private final class AllocatingThread: Sendable {
  private let running = Atomic(true)
  private let started = DispatchSemaphore(value: 0)
  private let finished = DispatchSemaphore(value: 0)

  init() {
    Thread.detachNewThread { [self] in
      started.signal()
      while running.load(ordering: .relaxed) {
        blackHole(Probe())
      }
      finished.signal()
    }
    started.wait()
  }

  func stop() {
    running.store(false, ordering: .relaxed)
    finished.wait()
  }
}

private final class Probe {}

private final class Observations: @unchecked Sendable {
  private let lock = NSLock()
  private var observed: [Bool?] = []

  var values: [Bool?] {
    lock.withLock { observed }
  }

  func append(_ value: Bool?) {
    lock.withLock { observed.append(value) }
  }
}
