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
