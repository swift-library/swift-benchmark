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
  public init() {}

  public func now() -> BenchmarkInstant {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return BenchmarkInstant(
      nanoseconds: Self.nanoseconds(usage.ru_utime) + Self.nanoseconds(usage.ru_stime))
  }

  private static func nanoseconds(_ time: timeval) -> UInt64 {
    UInt64(max(0, Int(time.tv_sec))) * 1_000_000_000 + UInt64(max(0, Int(time.tv_usec))) * 1_000
  }
}

/// Reads the highest physical memory footprint the process has reached.
enum PhysicalFootprint {
  /// The peak footprint in bytes, or `nil` where the platform does not report it.
  static func peak() -> UInt64? {
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
      return UInt64(info.ledger_phys_footprint_peak)
    #elseif os(Linux)
      var usage = rusage()
      guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        return nil
      }
      return UInt64(max(0, Int(usage.ru_maxrss))) * 1_024
    #else
      return nil
    #endif
  }
}

/// Accumulates the values a workload records with ``Benchmark/record(_:for:)``
/// during one sample.
final class CustomMetricRecorder: Sendable {
  @TaskLocal static var current: CustomMetricRecorder?

  private let totals = Mutex<[Benchmark.Metric: Double]>([:])

  func add(_ value: Double, for metric: Benchmark.Metric) {
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
  /// batch size, like the built-in metrics. Outside a measured sample the call
  /// does nothing.
  public static func record(_ value: Double, for metric: Metric) {
    CustomMetricRecorder.current?.add(value, for: metric)
  }
}

/// Counts Swift heap allocations and strong reference-counting operations
/// through the Swift runtime's instrumentation hooks.
///
/// The hooks are process-wide, so counts include every thread. Counting passes
/// run one at a time.
enum RuntimeCounters {
  struct Counts: Sendable, Equatable {
    var allocations: Int
    var allocatedBytes: Int
    var retains: Int
    var releases: Int
  }

  private static let gate = CountingGate()

  /// Runs `body` with the hooks installed. The counts are `nil` when the
  /// runtime does not expose the hooks.
  static func counting(_ body: () async throws -> Void) async throws -> Counts? {
    await gate.acquire()
    do {
      let counts = try await countWithHooks(body)
      await gate.release()
      return counts
    } catch {
      await gate.release()
      throw error
    }
  }

  private static func countWithHooks(_ body: () async throws -> Void) async throws -> Counts? {
    guard let hooks = RuntimeHooks.resolve() else {
      try await body()
      return nil
    }
    resetCounters()
    hooks.install()
    defer {
      hooks.uninstall()
    }
    try await body()
    return Counts(
      allocations: allocationCount.load(ordering: .relaxed),
      allocatedBytes: allocatedByteCount.load(ordering: .relaxed),
      retains: retainCount.load(ordering: .relaxed),
      releases: releaseCount.load(ordering: .relaxed)
    )
  }

  private static func resetCounters() {
    allocationCount.store(0, ordering: .relaxed)
    allocatedByteCount.store(0, ordering: .relaxed)
    retainCount.store(0, ordering: .relaxed)
    releaseCount.store(0, ordering: .relaxed)
  }
}

private actor CountingGate {
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    guard busy else {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    guard !waiters.isEmpty else {
      busy = false
      return
    }
    waiters.removeFirst().resume()
  }
}

private let allocationCount = Atomic<Int>(0)
private let allocatedByteCount = Atomic<Int>(0)
private let retainCount = Atomic<Int>(0)
private let releaseCount = Atomic<Int>(0)

private typealias AllocObjectFunction =
  @convention(c) (UnsafeRawPointer?, Int, Int) -> UnsafeMutableRawPointer?
private typealias RetainFunction =
  @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
private typealias ReleaseFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias RetainNFunction =
  @convention(c) (UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
private typealias ReleaseNFunction = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Void

// The original functions, set before a counting function is installed and
// read only by the counting functions.
nonisolated(unsafe) private var originalAllocObject: AllocObjectFunction?
nonisolated(unsafe) private var originalRetain: RetainFunction?
nonisolated(unsafe) private var originalRelease: ReleaseFunction?
nonisolated(unsafe) private var originalRetainN: RetainNFunction?
nonisolated(unsafe) private var originalReleaseN: ReleaseNFunction?

private let countingAllocObject: AllocObjectFunction = { metadata, size, alignmentMask in
  allocationCount.wrappingAdd(1, ordering: .relaxed)
  allocatedByteCount.wrappingAdd(size, ordering: .relaxed)
  return originalAllocObject!(metadata, size, alignmentMask)
}

private let countingRetain: RetainFunction = { object in
  retainCount.wrappingAdd(1, ordering: .relaxed)
  return originalRetain!(object)
}

private let countingRelease: ReleaseFunction = { object in
  releaseCount.wrappingAdd(1, ordering: .relaxed)
  originalRelease!(object)
}

private let countingRetainN: RetainNFunction = { object, count in
  retainCount.wrappingAdd(Int(count), ordering: .relaxed)
  return originalRetainN!(object, count)
}

private let countingReleaseN: ReleaseNFunction = { object, count in
  releaseCount.wrappingAdd(Int(count), ordering: .relaxed)
  originalReleaseN!(object, count)
}

/// The runtime's hook slots. The Swift runtime calls through these function
/// pointers only while its swizzling flag is set, so installation sets the
/// flag and uninstallation restores it.
private struct RuntimeHooks {
  let allocObject: UnsafeMutablePointer<AllocObjectFunction>
  let retain: UnsafeMutablePointer<RetainFunction>
  let release: UnsafeMutablePointer<ReleaseFunction>
  let retainN: UnsafeMutablePointer<RetainNFunction>
  let releaseN: UnsafeMutablePointer<ReleaseNFunction>
  let swizzlingFlag: UnsafeMutableRawPointer?

  static func resolve() -> RuntimeHooks? {
    guard let allocObject = symbol("_swift_allocObject"),
      let retain = symbol("_swift_retain"),
      let release = symbol("_swift_release"),
      let retainN = symbol("_swift_retain_n"),
      let releaseN = symbol("_swift_release_n")
    else {
      return nil
    }
    return RuntimeHooks(
      allocObject: allocObject.assumingMemoryBound(to: AllocObjectFunction.self),
      retain: retain.assumingMemoryBound(to: RetainFunction.self),
      release: release.assumingMemoryBound(to: ReleaseFunction.self),
      retainN: retainN.assumingMemoryBound(to: RetainNFunction.self),
      releaseN: releaseN.assumingMemoryBound(to: ReleaseNFunction.self),
      swizzlingFlag: symbol(
        "_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly")
    )
  }

  nonisolated(unsafe) private static var previousSwizzlingFlag: UInt8 = 0

  func install() {
    originalAllocObject = allocObject.pointee
    originalRetain = retain.pointee
    originalRelease = release.pointee
    originalRetainN = retainN.pointee
    originalReleaseN = releaseN.pointee
    allocObject.pointee = countingAllocObject
    retain.pointee = countingRetain
    release.pointee = countingRelease
    retainN.pointee = countingRetainN
    releaseN.pointee = countingReleaseN
    if let swizzlingFlag {
      Self.previousSwizzlingFlag = swizzlingFlag.load(as: UInt8.self)
      swizzlingFlag.storeBytes(of: 1, as: UInt8.self)
    }
  }

  func uninstall() {
    if let swizzlingFlag {
      swizzlingFlag.storeBytes(of: Self.previousSwizzlingFlag, as: UInt8.self)
    }
    allocObject.pointee = originalAllocObject!
    retain.pointee = originalRetain!
    release.pointee = originalRelease!
    retainN.pointee = originalRetainN!
    releaseN.pointee = originalReleaseN!
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
