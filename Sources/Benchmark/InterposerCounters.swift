// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The counts of the interposer library, which a counting host process loads
/// before any other library: system allocator calls on every thread, and on
/// Linux the Swift runtime's allocations and reference counting.
///
/// The library's functions are found by name, so a process without it, such
/// as a test process, counts nothing here.
struct InterposerCounters: Sendable {
  struct Counts: Sendable, Equatable {
    var heapAllocations: UInt64
    var heapAllocatedBytes: UInt64
    var heapFrees: UInt64
    /// The Swift runtime counts, where the library keeps them.
    var runtime: RuntimeCounters.Counts?
  }

  private typealias ControlFunction = @convention(c) () -> Void
  private typealias CountFunction = @convention(c) (UInt32) -> UInt64

  /// The library loaded into this process, if any.
  static let loaded = InterposerCounters()

  private let startFunction: ControlFunction
  private let stopFunction: ControlFunction
  private let count: CountFunction

  private init?() {
    guard let start = Self.symbol("benchmark_interposer_start"),
      let stop = Self.symbol("benchmark_interposer_stop"),
      let count = Self.symbol("benchmark_interposer_count")
    else {
      return nil
    }
    self.startFunction = unsafeBitCast(start, to: ControlFunction.self)
    self.stopFunction = unsafeBitCast(stop, to: ControlFunction.self)
    self.count = unsafeBitCast(count, to: CountFunction.self)
  }

  /// Resets the counts and starts counting on every thread. Callers hold
  /// the ``MeasurementGate`` until ``stop()``.
  func start() {
    startFunction()
  }

  /// Stops counting; the counts keep their values until the next start.
  func stop() {
    stopFunction()
  }

  /// The counts between the last start and stop, or `nil` where the library
  /// counts nothing on this platform.
  func counts() -> Counts? {
    // The indices are the library's `benchmark_interposer_counter` values.
    let heapAllocations = count(0)
    guard heapAllocations != .max else {
      return nil
    }
    let swiftAllocations = count(3)
    let runtime =
      swiftAllocations == .max
      ? nil
      : RuntimeCounters.Counts(
        allocations: Int(swiftAllocations),
        allocatedBytes: Int(count(4)),
        retains: Int(count(5)),
        releases: Int(count(6))
      )
    return Counts(
      heapAllocations: heapAllocations,
      heapAllocatedBytes: count(1),
      heapFrees: count(2),
      runtime: runtime
    )
  }

  private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
    #if canImport(Darwin)
      // RTLD_DEFAULT
      dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    #elseif canImport(Glibc)
      dlsym(nil, name)
    #else
      nil
    #endif
  }
}
