// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

/// A clock whose readings advance by `step` nanoseconds each time it is read.
struct StepClock: BenchmarkClock {
  let step: UInt64
  private let state = StepClockState()

  init(step: UInt64) {
    self.step = step
  }

  func now() -> BenchmarkInstant {
    state.advance(by: step)
  }
}

private final class StepClockState: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 0

  func advance(by step: UInt64) -> BenchmarkInstant {
    lock.withLock {
      value += step
      return BenchmarkInstant(nanoseconds: value)
    }
  }
}

/// A runner whose every sample measures `step` nanoseconds of wall-clock time
/// and nothing else.
func exactRunner(step: UInt64) -> BenchmarkRunner {
  BenchmarkRunner(clock: StepClock(step: step), cpuClock: nil, countsAllocations: false)
}

final class Counter: @unchecked Sendable {
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
