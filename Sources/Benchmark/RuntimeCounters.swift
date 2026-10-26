// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

#if canImport(Darwin)
  import Darwin
  import Synchronization
#endif

/// Counts Swift runtime heap allocations and strong reference-counting
/// operations through the Swift runtime's instrumentation hooks.
///
/// The hooks are process-wide, so counts include every thread. Callers hold
/// the ``MeasurementGate`` while counting. Only Apple platforms count: on
/// Linux, routing reference counting through the hook slots crashed and
/// corrupted memory, so nothing is counted there.
enum RuntimeCounters {
  struct Counts: Sendable, Equatable {
    var allocations: Int
    var allocatedBytes: Int
    var retains: Int
    var releases: Int
  }

  /// Runs `body` with the hooks installed. The counts are `nil` where the
  /// runtime does not expose the hooks or the platform does not count.
  static func counting(_ body: () async throws -> Void) async throws -> Counts? {
    #if canImport(Darwin)
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
    #else
      try await body()
      return nil
    #endif
  }

  /// Sets the runtime's switch for calling through the hook slots back to
  /// its value before the first counting pass.
  ///
  /// A thread inside the runtime's allocation path when a counting pass ends
  /// can set the switch again, which leaves every later retain and release
  /// on the slower hook path. Callers restore it before timing a step, long
  /// after any counting pass has ended.
  static func restoreRuntimeSwitch() {
    #if canImport(Darwin)
      runtimeHookSlots?.restoreSwizzlingFlag()
    #endif
  }

  /// Whether the runtime calls through the hook slots, or `nil` where it has
  /// no such switch or the platform does not count.
  static var callsThroughHookSlots: Bool? {
    #if canImport(Darwin)
      runtimeHookSlots?.swizzlingFlag.map { $0.load(as: UInt8.self) != 0 }
    #else
      nil
    #endif
  }
}

#if canImport(Darwin)
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
    /// The runtime calls through the hook slots only while this flag is set,
    /// and sets it itself when an allocation finds a replaced slot. It is a
    /// one-byte atomic the runtime reads with relaxed loads; a plain byte load
    /// or store reads or writes it whole.
    let swizzlingFlag: UnsafeMutableRawPointer?
    let originalSwizzlingFlag: UInt8?
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
      self.originalSwizzlingFlag = self.swizzlingFlag?.load(as: UInt8.self)
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
      swizzlingFlag?.storeBytes(of: 1, as: UInt8.self)
    }

    /// Restores the slots, then the flag, which an allocation finding a
    /// replaced slot would set again.
    func uninstall() {
      allocObject.pointee = originalAllocObject
      retain.pointee = originalRetain
      release.pointee = originalRelease
      retainN.pointee = originalRetainN
      releaseN.pointee = originalReleaseN
      restoreSwizzlingFlag()
    }

    func restoreSwizzlingFlag() {
      guard let swizzlingFlag, let originalSwizzlingFlag,
        swizzlingFlag.load(as: UInt8.self) != originalSwizzlingFlag
      else {
        return
      }
      swizzlingFlag.storeBytes(of: originalSwizzlingFlag, as: UInt8.self)
    }

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
      // RTLD_DEFAULT
      dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
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
#endif
