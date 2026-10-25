// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// A benchmark body ready to call.
///
/// Synchronous bodies stay synchronous so the runner can call them in a batch
/// without an `await` between calls.
enum BenchmarkWorkload: Sendable {
  case synchronous(@Sendable () throws -> Void)
  case asynchronous(@Sendable () async throws -> Void)

  func call() async throws {
    switch self {
    case .synchronous(let body):
      try body()
    case .asynchronous(let body):
      try await body()
    }
  }

  /// Calls the body `count` times between two readings of `clock` and returns
  /// the readings.
  func callTimed(
    _ count: Int,
    clock: any BenchmarkClock
  ) async throws -> (start: BenchmarkInstant, end: BenchmarkInstant) {
    switch self {
    case .synchronous(let body):
      return try Self.callSynchronously(body, count: count, clock: clock)
    case .asynchronous(let body):
      let start = clock.now()
      for _ in 0..<count {
        try await body()
      }
      return (start, clock.now())
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
    clock: any BenchmarkClock
  ) throws -> (start: BenchmarkInstant, end: BenchmarkInstant) {
    let start = clock.now()
    for _ in 0..<count {
      try body()
    }
    return (start, clock.now())
  }
}
