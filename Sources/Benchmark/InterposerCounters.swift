// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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

  /// A call stack the library recorded, innermost return address first.
  struct RecordedStack: Sendable, Equatable {
    var frames: [UInt]
    var allocations: Int
    var bytes: Int
  }

  /// The library's `benchmark_interposer_counter` values, from
  /// `_BenchmarkInterposer.h`.
  private enum Counter: UInt32 {
    case heapAllocations = 0
    case heapAllocatedBytes = 1
    case heapFrees = 2
    case swiftAllocations = 3
    case swiftAllocatedBytes = 4
    case swiftRetains = 5
    case swiftReleases = 6
  }

  /// The library's `benchmark_interposer_records_sites` option.
  private static let recordsSites: UInt32 = 1

  private typealias StartFunction = @convention(c) (UInt32) -> Void
  private typealias StopFunction = @convention(c) () -> Void
  private typealias CountFunction = @convention(c) (UInt32) -> UInt64
  private typealias SiteSlotsFunction = @convention(c) () -> UInt32
  private typealias SiteFunction =
    @convention(c) (
      UInt32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UInt32,
      UnsafeMutablePointer<UInt64>?, UnsafeMutablePointer<UInt64>?
    ) -> UInt32

  /// The library loaded into this process, if any.
  static let loaded = InterposerCounters()

  private let startFunction: StartFunction
  private let stopFunction: StopFunction
  private let count: CountFunction
  private let siteSlots: SiteSlotsFunction
  private let site: SiteFunction

  private init?() {
    guard let start = dynamicSymbol("benchmark_interposer_start"),
      let stop = dynamicSymbol("benchmark_interposer_stop"),
      let count = dynamicSymbol("benchmark_interposer_count"),
      let siteSlots = dynamicSymbol("benchmark_interposer_site_slots"),
      let site = dynamicSymbol("benchmark_interposer_site")
    else {
      return nil
    }
    self.startFunction = unsafeBitCast(start, to: StartFunction.self)
    self.stopFunction = unsafeBitCast(stop, to: StopFunction.self)
    self.count = unsafeBitCast(count, to: CountFunction.self)
    self.siteSlots = unsafeBitCast(siteSlots, to: SiteSlotsFunction.self)
    self.site = unsafeBitCast(site, to: SiteFunction.self)
  }

  /// Resets the counts and starts counting on every thread, recording the
  /// call stack of each allocation when `recordingSites` is set. Callers
  /// hold the ``MeasurementGate`` until ``stop()``.
  func start(recordingSites: Bool) {
    startFunction(recordingSites ? Self.recordsSites : 0)
  }

  /// Stops counting; the counts keep their values until the next start.
  func stop() {
    stopFunction()
  }

  /// The counts between the last start and stop, or `nil` where the library
  /// counts nothing on this platform.
  func counts() -> Counts? {
    let heapAllocations = value(.heapAllocations)
    guard heapAllocations != .max else {
      return nil
    }
    let swiftAllocations = value(.swiftAllocations)
    let runtime =
      swiftAllocations == .max
      ? nil
      : RuntimeCounters.Counts(
        allocations: Int(swiftAllocations),
        allocatedBytes: Int(value(.swiftAllocatedBytes)),
        retains: Int(value(.swiftRetains)),
        releases: Int(value(.swiftReleases))
      )
    return Counts(
      heapAllocations: heapAllocations,
      heapAllocatedBytes: value(.heapAllocatedBytes),
      heapFrees: value(.heapFrees),
      runtime: runtime
    )
  }

  /// The library's value of `counter`, or `UInt64.max` where it does not
  /// count it.
  private func value(_ counter: Counter) -> UInt64 {
    count(counter.rawValue)
  }

  /// The stacks recorded between the last start and stop, or none when that
  /// start recorded no sites.
  func recordedStacks() -> [RecordedStack] {
    let capacity: UInt32 = 64
    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: Int(capacity))
    var stacks: [RecordedStack] = []
    for index in 0..<siteSlots() {
      var allocations: UInt64 = 0
      var bytes: UInt64 = 0
      let depth = site(index, &frames, capacity, &allocations, &bytes)
      guard depth > 0 || allocations > 0 else {
        continue
      }
      stacks.append(
        RecordedStack(
          frames: frames.prefix(Int(depth)).map { UInt(bitPattern: $0) },
          allocations: Int(allocations),
          bytes: Int(bytes)
        ))
    }
    return stacks
  }
}
