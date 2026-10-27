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
  /// A body that takes a fresh input on every call: `prepare(count)` makes
  /// the inputs of a batch before the batch is measured.
  case prepared(@Sendable (Int) async throws -> PreparedBatch)

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
  /// `countsProcessEvents` is set. Prepared inputs are made before the first
  /// reading and released after the last.
  func callTimed(
    _ count: Int,
    clock: any BenchmarkClock,
    cpuClock: (any BenchmarkClock)? = nil,
    countsProcessEvents: Bool = false
  ) async throws -> Interval {
    let timer = Timer(clock: clock, cpuClock: cpuClock, countsProcessEvents: countsProcessEvents)
    switch self {
    case .synchronous(let body):
      return try timer.timeSynchronously {
        var remaining = count
        while remaining > 0 {
          try body()
          remaining -= 1
        }
      }
    case .asynchronous(let body):
      return try await timer.timeAsynchronously {
        var remaining = count
        while remaining > 0 {
          try await body()
          remaining -= 1
        }
      }
    case .prepared(let prepare):
      let batch = try await Self.prepareBatch(count, prepare)
      defer { Self.discard(batch) }
      switch batch.calls {
      case .synchronous(let calls):
        return try timer.timeSynchronously(calls)
      case .asynchronous(let calls):
        return try await timer.timeAsynchronously(calls)
      }
    }
  }

  /// Calls the body `count` times inside `measure`, which wraps the calls in
  /// a measurement of its own. Prepared inputs are made before `measure`
  /// starts and released after it returns.
  func callMeasured(
    _ count: Int,
    _ measure: (_ calls: () async throws -> Void) async throws -> Void
  ) async throws {
    switch self {
    case .synchronous(let body):
      try await measure {
        var remaining = count
        while remaining > 0 {
          try body()
          remaining -= 1
        }
      }
    case .asynchronous(let body):
      try await measure {
        var remaining = count
        while remaining > 0 {
          try await body()
          remaining -= 1
        }
      }
    case .prepared(let prepare):
      let batch = try await Self.prepareBatch(count, prepare)
      defer { Self.discard(batch) }
      switch batch.calls {
      case .synchronous(let calls):
        try await measure { try calls() }
      case .asynchronous(let calls):
        try await measure { try await calls() }
      }
    }
  }

  /// Makes a batch's inputs with no sample recording custom metrics, so what
  /// setup records is not the workload's.
  private static func prepareBatch(
    _ count: Int, _ prepare: @Sendable (Int) async throws -> PreparedBatch
  ) async throws -> PreparedBatch {
    try await CustomMetricRecorder.$current.withValue(nil) {
      try await prepare(count)
    }
  }

  /// Releases a batch's inputs with no sample recording custom metrics.
  private static func discard(_ batch: PreparedBatch) {
    CustomMetricRecorder.$current.withValue(nil) {
      batch.discard()
    }
  }

  /// Takes the readings of one timed batch.
  private struct Timer {
    var clock: any BenchmarkClock
    var cpuClock: (any BenchmarkClock)?
    var countsProcessEvents: Bool

    func timeSynchronously(_ calls: () throws -> Void) throws -> Interval {
      let counters =
        countsProcessEvents ? ProcessCounterWindow(batchRunsOnCallingThread: true) : nil
      let cpuStart = cpuClock?.now()
      let start = clock.now()
      do {
        try calls()
      } catch {
        _ = counters?.close()
        throw error
      }
      let end = clock.now()
      let cpuEnd = cpuClock?.now()
      return Interval(
        start: start, end: end, cpuStart: cpuStart, cpuEnd: cpuEnd,
        counters: counters?.close() ?? [:])
    }

    func timeAsynchronously(_ calls: () async throws -> Void) async throws -> Interval {
      let counters =
        countsProcessEvents ? ProcessCounterWindow(batchRunsOnCallingThread: false) : nil
      let cpuStart = cpuClock?.now()
      let start = clock.now()
      do {
        try await calls()
      } catch {
        _ = counters?.close()
        throw error
      }
      let end = clock.now()
      let cpuEnd = cpuClock?.now()
      return Interval(
        start: start, end: end, cpuStart: cpuStart, cpuEnd: cpuEnd,
        counters: counters?.close() ?? [:])
    }
  }
}

/// The inputs of one batch of a workload with per-call setup, and the calls
/// that consume them.
///
/// The inputs live in one buffer that the calls index, so a call adds no
/// access tracking, reference counting or allocation to the measurement.
/// They are released by ``discard()``, which the runner calls after every
/// measurement of the batch, so freeing them is neither timed nor counted.
final class PreparedBatch {
  enum Calls {
    case synchronous(() throws -> Void)
    case asynchronous(() async throws -> Void)
  }

  let calls: Calls
  private var release: (() -> Void)?

  private init(calls: Calls, release: @escaping () -> Void) {
    self.calls = calls
    self.release = release
  }

  deinit {
    discard()
  }

  /// Releases the inputs.
  func discard() {
    release?()
    release = nil
  }

  /// Makes `count` inputs with `setup` for synchronous calls of `operation`.
  static func make<Input>(
    count: Int,
    setup: () throws -> Input,
    operation: @escaping @Sendable (inout Input) throws -> Void
  ) throws -> PreparedBatch {
    let inputs = try Inputs(count: count, setup: setup)
    return PreparedBatch(
      calls: .synchronous {
        var index = 0
        while index < inputs.count {
          try operation(&inputs.start[index])
          index += 1
        }
      },
      release: inputs.release
    )
  }

  /// Makes `count` inputs with `setup` for asynchronous calls of `operation`.
  static func make<Input>(
    count: Int,
    setup: () async throws -> Input,
    operation: @escaping @Sendable (inout Input) async throws -> Void
  ) async throws -> PreparedBatch {
    let inputs = try await Inputs(count: count, setup: setup)
    return PreparedBatch(
      calls: .asynchronous {
        var index = 0
        while index < inputs.count {
          try await operation(&inputs.start[index])
          index += 1
        }
      },
      release: inputs.release
    )
  }

  private struct Inputs<Input> {
    let start: UnsafeMutablePointer<Input>
    let count: Int

    init(count: Int, setup: () throws -> Input) throws {
      start = .allocate(capacity: count)
      var made = 0
      do {
        while made < count {
          (start + made).initialize(to: try setup())
          made += 1
        }
      } catch {
        start.deinitialize(count: made)
        start.deallocate()
        throw error
      }
      self.count = count
    }

    init(count: Int, setup: () async throws -> Input) async throws {
      start = .allocate(capacity: count)
      var made = 0
      do {
        while made < count {
          (start + made).initialize(to: try await setup())
          made += 1
        }
      } catch {
        start.deinitialize(count: made)
        start.deallocate()
        throw error
      }
      self.count = count
    }

    func release() {
      start.deinitialize(count: count)
      start.deallocate()
    }
  }
}
