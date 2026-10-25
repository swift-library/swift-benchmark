// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Synchronization

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#endif

/// A clock that reads the process's user plus system CPU time.
public struct ProcessCPUClock: BenchmarkClock {
  /// Creates a clock that reads process CPU time with `getrusage`.
  public init() {}

  public func now() -> BenchmarkInstant {
    let usage = ResourceUsage.current()
    return BenchmarkInstant(
      nanoseconds: Self.nanoseconds(usage.ru_utime) + Self.nanoseconds(usage.ru_stime))
  }

  private static func nanoseconds(_ time: timeval) -> UInt64 {
    UInt64(max(0, Int(time.tv_sec))) * 1_000_000_000 + UInt64(max(0, Int(time.tv_usec))) * 1_000
  }
}

private enum ResourceUsage {
  static func current() -> rusage {
    #if canImport(Darwin)
      let who = RUSAGE_SELF
    #else
      // Glibc imports RUSAGE_SELF as an enumeration case.
      let who = RUSAGE_SELF.rawValue
    #endif
    var usage = rusage()
    getrusage(who, &usage)
    return usage
  }
}

/// Reads the process's physical memory footprint.
enum PhysicalFootprint {
  /// The current footprint and the highest footprint the process has reached,
  /// in bytes, or `nil` where the platform does not report them.
  static func read() -> (current: UInt64, peak: UInt64)? {
    #if canImport(Darwin)
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
      let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
      }
      guard result == KERN_SUCCESS else {
        return nil
      }
      return (UInt64(info.phys_footprint), UInt64(info.ledger_phys_footprint_peak))
    #elseif os(Linux)
      guard let current = residentBytesFromProcStatm() else {
        return nil
      }
      let peak = UInt64(max(0, Int(ResourceUsage.current().ru_maxrss))) * 1_024
      return (current, max(current, peak))
    #else
      return nil
    #endif
  }

  #if os(Linux)
    /// The resident set size; the second field of `/proc/self/statm` counts
    /// resident pages.
    private static func residentBytesFromProcStatm() -> UInt64? {
      guard let file = fopen("/proc/self/statm", "r") else {
        return nil
      }
      defer { fclose(file) }
      var buffer = [CChar](repeating: 0, count: 128)
      guard fgets(&buffer, Int32(buffer.count), file) != nil else {
        return nil
      }
      let line = String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      let fields = line.split(separator: " ")
      guard fields.count >= 2, let pages = UInt64(fields[1]) else {
        return nil
      }
      return pages * UInt64(sysconf(Int32(_SC_PAGESIZE)))
    }
  #endif
}

/// Accumulates the values a workload records with ``Benchmark/record(_:for:)``
/// during one sample.
final class CustomMetricRecorder: Sendable {
  @TaskLocal static var current: CustomMetricRecorder?

  private let totals = Mutex<[Benchmark.Metric: Double]>([:])

  func add(_ value: Double, for metric: Benchmark.Metric) {
    guard !Benchmark.Metric.builtIn.contains(metric) else {
      return
    }
    totals.withLock { $0[metric, default: 0] += value }
  }

  func values() -> [Benchmark.Metric: Double] {
    totals.withLock { $0 }
  }
}

extension Benchmark {
  /// Adds `value` to `metric` for the sample being measured.
  ///
  /// Values recorded during one sample are summed and divided by the sample's
  /// batch size, like the built-in metrics. The call does nothing outside a
  /// measured sample and for the names of ``Metric/builtIn`` metrics, which
  /// the runner measures itself.
  public static func record(_ value: Double, for metric: Metric) {
    CustomMetricRecorder.current?.add(value, for: metric)
  }
}

/// Gives one step at a time exclusive use of the process for measurement.
///
/// The counting pass installs process-wide runtime hooks, and parallel
/// measurements disturb each other's times, so a runner holds the gate from
/// a step's warmup through its counting pass. A workload must not run a
/// benchmark runner itself, because it would wait for its own step.
actor MeasurementGate {
  static let shared = MeasurementGate()

  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  /// Runs `body` once no other step is measuring.
  nonisolated func withExclusiveAccess<T: Sendable>(
    _ body: () async throws -> T
  ) async throws -> T {
    await acquire()
    do {
      let result = try await body()
      await release()
      return result
    } catch {
      await release()
      throw error
    }
  }

  private func acquire() async {
    guard busy else {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  private func release() {
    guard !waiters.isEmpty else {
      busy = false
      return
    }
    waiters.removeFirst().resume()
  }
}

/// Counts Swift heap allocations and strong reference-counting operations
/// through the Swift runtime's instrumentation hooks.
///
/// The hooks are process-wide, so counts include every thread. Callers hold
/// the ``MeasurementGate`` while counting.
enum RuntimeCounters {
  struct Counts: Sendable, Equatable {
    var allocations: Int
    var allocatedBytes: Int
    var retains: Int
    var releases: Int
  }

  /// Runs `body` with the hooks installed. The counts are `nil` when the
  /// runtime does not expose the hooks.
  static func counting(_ body: () async throws -> Void) async throws -> Counts? {
    guard let slots = runtimeHookSlots else {
      try await body()
      return nil
    }
    allocationCount.store(0, ordering: .relaxed)
    allocatedByteCount.store(0, ordering: .relaxed)
    retainCount.store(0, ordering: .relaxed)
    releaseCount.store(0, ordering: .relaxed)
    slots.install()
    defer {
      slots.uninstall()
    }
    try await body()
    return Counts(
      allocations: allocationCount.load(ordering: .relaxed),
      allocatedBytes: allocatedByteCount.load(ordering: .relaxed),
      retains: retainCount.load(ordering: .relaxed),
      releases: releaseCount.load(ordering: .relaxed)
    )
  }
}

private let allocationCount = Atomic<Int>(0)
private let allocatedByteCount = Atomic<Int>(0)
private let retainCount = Atomic<Int>(0)
private let releaseCount = Atomic<Int>(0)
private let previousSwizzlingFlag = Atomic<UInt8>(0)

private typealias AllocObjectFunction =
  @convention(c) (UnsafeRawPointer?, Int, Int) -> UnsafeMutableRawPointer?
private typealias RetainFunction =
  @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias ReleaseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias RetainNFunction =
  @convention(c) (UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
private typealias ReleaseNFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Void

/// The runtime's hook slots and its own implementations, resolved once before
/// the first installation and never changed afterwards.
///
/// The counting functions read this global from inside the runtime's
/// allocation and reference-counting paths, so it holds only trivial values:
/// reading it never retains, which would re-enter a counting function. A
/// counting function still running on another thread after uninstallation
/// forwards to the runtime's implementation.
private let runtimeHookSlots = RuntimeHookSlots()

private struct RuntimeHookSlots: @unchecked Sendable {
  let allocObject: UnsafeMutablePointer<AllocObjectFunction>
  let retain: UnsafeMutablePointer<RetainFunction>
  let release: UnsafeMutablePointer<ReleaseFunction>
  let retainN: UnsafeMutablePointer<RetainNFunction>
  let releaseN: UnsafeMutablePointer<ReleaseNFunction>
  /// The runtime calls through the hook slots only while this flag is set.
  let swizzlingFlag: UnsafeMutableRawPointer?
  let originalAllocObject: AllocObjectFunction
  let originalRetain: RetainFunction
  let originalRelease: ReleaseFunction
  let originalRetainN: RetainNFunction
  let originalReleaseN: ReleaseNFunction

  init?() {
    guard let allocObject = Self.symbol("_swift_allocObject"),
      let retain = Self.symbol("_swift_retain"),
      let release = Self.symbol("_swift_release"),
      let retainN = Self.symbol("_swift_retain_n"),
      let releaseN = Self.symbol("_swift_release_n")
    else {
      return nil
    }
    self.allocObject = allocObject.assumingMemoryBound(to: AllocObjectFunction.self)
    self.retain = retain.assumingMemoryBound(to: RetainFunction.self)
    self.release = release.assumingMemoryBound(to: ReleaseFunction.self)
    self.retainN = retainN.assumingMemoryBound(to: RetainNFunction.self)
    self.releaseN = releaseN.assumingMemoryBound(to: ReleaseNFunction.self)
    self.swizzlingFlag = Self.symbol(
      "_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly")
    self.originalAllocObject = self.allocObject.pointee
    self.originalRetain = self.retain.pointee
    self.originalRelease = self.release.pointee
    self.originalRetainN = self.retainN.pointee
    self.originalReleaseN = self.releaseN.pointee
  }

  func install() {
    allocObject.pointee = countingAllocObject
    retain.pointee = countingRetain
    release.pointee = countingRelease
    retainN.pointee = countingRetainN
    releaseN.pointee = countingReleaseN
    if let swizzlingFlag {
      previousSwizzlingFlag.store(swizzlingFlag.load(as: UInt8.self), ordering: .relaxed)
      swizzlingFlag.storeBytes(of: 1, as: UInt8.self)
    }
  }

  func uninstall() {
    if let swizzlingFlag {
      swizzlingFlag.storeBytes(
        of: previousSwizzlingFlag.load(ordering: .relaxed), as: UInt8.self)
    }
    allocObject.pointee = originalAllocObject
    retain.pointee = originalRetain
    release.pointee = originalRelease
    retainN.pointee = originalRetainN
    releaseN.pointee = originalReleaseN
  }

  private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
    #if canImport(Darwin)
      // RTLD_DEFAULT
      dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    #else
      dlsym(nil, name)
    #endif
  }
}

private let countingAllocObject: AllocObjectFunction = { metadata, size, alignmentMask in
  allocationCount.wrappingAdd(1, ordering: .relaxed)
  allocatedByteCount.wrappingAdd(size, ordering: .relaxed)
  return runtimeHookSlots.unsafelyUnwrapped.originalAllocObject(metadata, size, alignmentMask)
}

private let countingRetain: RetainFunction = { object in
  retainCount.wrappingAdd(1, ordering: .relaxed)
  return runtimeHookSlots.unsafelyUnwrapped.originalRetain(object)
}

private let countingRelease: ReleaseFunction = { object in
  releaseCount.wrappingAdd(1, ordering: .relaxed)
  runtimeHookSlots.unsafelyUnwrapped.originalRelease(object)
}

private let countingRetainN: RetainNFunction = { object, count in
  retainCount.wrappingAdd(Int(count), ordering: .relaxed)
  return runtimeHookSlots.unsafelyUnwrapped.originalRetainN(object, count)
}

private let countingReleaseN: ReleaseNFunction = { object, count in
  releaseCount.wrappingAdd(Int(count), ordering: .relaxed)
  runtimeHookSlots.unsafelyUnwrapped.originalReleaseN(object, count)
}
