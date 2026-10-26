// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// A benchmark body ready to call.
///
/// Synchronous bodies stay synchronous so the runner can call them in a batch
/// without an `await` between calls. Batches count their calls down in a
/// `while` loop: a range loop allocates in unoptimized builds, and counting
/// would charge those allocations to the workload.
enum BenchmarkWorkload: Sendable {
  case synchronous(@Sendable () throws -> Void)
  case asynchronous(@Sendable () async throws -> Void)

  /// Readings taken immediately around one timed batch: the process
  /// counters outside the CPU clock, and the CPU clock outside the wall
  /// clock, all around the same calls.
  struct Interval: Sendable {
    var start: BenchmarkInstant
    var end: BenchmarkInstant
    var cpuStart: BenchmarkInstant?
    var cpuEnd: BenchmarkInstant?
    /// Process counter totals for the whole batch, by metric.
    var counters: [Benchmark.Metric: Double] = [:]

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
  /// given, `cpuClock`, and counts process events around them when
  /// `countsProcessEvents` is set.
  func callTimed(
    _ count: Int,
    clock: any BenchmarkClock,
    cpuClock: (any BenchmarkClock)? = nil,
    countsProcessEvents: Bool = false
  ) async throws -> Interval {
    switch self {
    case .synchronous(let body):
      return try Self.callSynchronously(
        body, count: count, clock: clock, cpuClock: cpuClock,
        countsProcessEvents: countsProcessEvents)
    case .asynchronous(let body):
      let counters =
        countsProcessEvents ? ProcessCounterWindow(batchRunsOnCallingThread: false) : nil
      let cpuStart = cpuClock?.now()
      let start = clock.now()
      var remaining = count
      while remaining > 0 {
        try await body()
        remaining -= 1
      }
      let end = clock.now()
      let cpuEnd = cpuClock?.now()
      return Interval(
        start: start, end: end, cpuStart: cpuStart, cpuEnd: cpuEnd,
        counters: counters?.close() ?? [:])
    }
  }

  /// Calls the body `count` times with no timing.
  func callRepeatedly(_ count: Int) async throws {
    var remaining = count
    switch self {
    case .synchronous(let body):
      while remaining > 0 {
        try body()
        remaining -= 1
      }
    case .asynchronous(let body):
      while remaining > 0 {
        try await body()
        remaining -= 1
      }
    }
  }

  private static func callSynchronously(
    _ body: @Sendable () throws -> Void,
    count: Int,
    clock: any BenchmarkClock,
    cpuClock: (any BenchmarkClock)?,
    countsProcessEvents: Bool
  ) throws -> Interval {
    let counters =
      countsProcessEvents ? ProcessCounterWindow(batchRunsOnCallingThread: true) : nil
    let cpuStart = cpuClock?.now()
    let start = clock.now()
    var remaining = count
    while remaining > 0 {
      try body()
      remaining -= 1
    }
    let end = clock.now()
    let cpuEnd = cpuClock?.now()
    return Interval(
      start: start, end: end, cpuStart: cpuStart, cpuEnd: cpuEnd,
      counters: counters?.close() ?? [:])
  }
}
