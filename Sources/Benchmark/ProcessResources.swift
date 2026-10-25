// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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

  /// The CPU time the process's threads have used so far.
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
