// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// A benchmark body ready to call.
///
/// Synchronous bodies stay synchronous so the runner can call them in a batch
/// without an `await` between calls.
enum BenchmarkWorkload: Sendable {
  case synchronous(@Sendable () throws -> Void)
  case asynchronous(@Sendable () async throws -> Void)

  /// Readings taken immediately around one timed batch: the CPU clock outside
  /// the wall clock, both around the same calls.
  struct Interval: Sendable {
    var start: BenchmarkInstant
    var end: BenchmarkInstant
    var cpuStart: BenchmarkInstant?
    var cpuEnd: BenchmarkInstant?

    var nanoseconds: UInt64 {
      start.duration(to: end)
    }

    var cpuNanoseconds: UInt64? {
      guard let cpuStart, let cpuEnd else {
        return nil
      }
      return cpuStart.duration(to: cpuEnd)
    }
  }

  /// Calls the body `count` times between readings of `clock` and, when
  /// given, `cpuClock`.
  func callTimed(
    _ count: Int,
    clock: any BenchmarkClock,
    cpuClock: (any BenchmarkClock)? = nil
  ) async throws -> Interval {
    switch self {
    case .synchronous(let body):
      return try Self.callSynchronously(body, count: count, clock: clock, cpuClock: cpuClock)
    case .asynchronous(let body):
      let cpuStart = cpuClock?.now()
      let start = clock.now()
      for _ in 0..<count {
        try await body()
      }
      let end = clock.now()
      return Interval(start: start, end: end, cpuStart: cpuStart, cpuEnd: cpuClock?.now())
    }
  }

  /// Calls the body `count` times with no timing.
  func callRepeatedly(_ count: Int) async throws {
    switch self {
    case .synchronous(let body):
      for _ in 0..<count {
        try body()
      }
    case .asynchronous(let body):
      for _ in 0..<count {
        try await body()
      }
    }
  }

  private static func callSynchronously(
    _ body: @Sendable () throws -> Void,
    count: Int,
    clock: any BenchmarkClock,
    cpuClock: (any BenchmarkClock)?
  ) throws -> Interval {
    let cpuStart = cpuClock?.now()
    let start = clock.now()
    for _ in 0..<count {
      try body()
    }
    let end = clock.now()
    return Interval(start: start, end: end, cpuStart: cpuStart, cpuEnd: cpuClock?.now())
  }
}
