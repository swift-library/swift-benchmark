// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

internal import _BenchmarkPlatform

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#endif

/// Hardware and operating system events counted around one timed batch:
/// instructions, cycles, context switches, page faults, system calls and disk
/// bytes, each where the platform counts it.
///
/// Apple platforms count instructions and cycles for the whole process. Linux
/// counts them for the thread that opens the window and the threads it
/// creates, so a window records them only when the batch runs on that thread.
struct ProcessCounterWindow {
  private let start: [Benchmark.Metric: UInt64]
  private let threadCounters: [(metric: Benchmark.Metric, counter: Int32)]

  /// Starts counting. `batchRunsOnCallingThread` says whether the whole batch
  /// runs on the calling thread.
  init(batchRunsOnCallingThread: Bool) {
    #if os(Linux)
      threadCounters =
        batchRunsOnCallingThread
        ? Self.openThreadCounters([
          (.instructions, benchmark_thread_counter_instructions),
          (.cycles, benchmark_thread_counter_cycles),
        ]) : []
    #else
      threadCounters = []
    #endif
    start = Self.processCounts()
  }

  /// The events counted since the window started, by metric, and stops
  /// counting.
  func close() -> [Benchmark.Metric: Double] {
    var totals: [Benchmark.Metric: Double] = [:]
    for (metric, counter) in threadCounters {
      var value: UInt64 = 0
      if benchmark_thread_counter_read(counter, &value) == 0 {
        totals[metric] = Double(value)
      }
      benchmark_thread_counter_close(counter)
    }
    let end = Self.processCounts()
    for (metric, value) in end {
      guard let started = start[metric] else {
        continue
      }
      totals[metric] = Double((value &- started) & Self.counterMask(for: metric))
    }
    return totals
  }

  /// The mask that keeps a count's difference correct across wrapping; the
  /// Mach event counters are 32 bits wide.
  private static func counterMask(for metric: Benchmark.Metric) -> UInt64 {
    #if canImport(Darwin)
      if metric == .contextSwitches || metric == .pageFaults || metric == .systemCalls {
        return UInt64(UInt32.max)
      }
    #endif
    return UInt64.max
  }

  #if os(Linux)
    private static func openThreadCounters(
      _ kinds: [(Benchmark.Metric, benchmark_thread_counter_kind)]
    ) -> [(metric: Benchmark.Metric, counter: Int32)] {
      kinds.compactMap { metric, kind in
        let counter = benchmark_thread_counter_open(kind)
        return counter < 0 ? nil : (metric, counter)
      }
    }
  #endif

  /// Process-wide counts the platform reports, by metric.
  private static func processCounts() -> [Benchmark.Metric: UInt64] {
    var counts: [Benchmark.Metric: UInt64] = [:]
    #if canImport(Darwin)
      var basic = task_inspect_basic_counts()
      var basicCount = mach_msg_type_number_t(
        MemoryLayout<task_inspect_basic_counts>.size / MemoryLayout<natural_t>.size)
      let inspected = withUnsafeMutablePointer(to: &basic) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
          task_inspect(
            mach_task_self_, task_inspect_flavor_t(TASK_INSPECT_BASIC_COUNTS.rawValue), $0,
            &basicCount)
        }
      }
      // A running process has always retired instructions; zero means the
      // hardware counters are unavailable, as in some virtual machines.
      if inspected == KERN_SUCCESS, basic.instructions > 0 {
        counts[.instructions] = basic.instructions
        counts[.cycles] = basic.cycles
      }
      var events = task_events_info()
      var eventsCount = mach_msg_type_number_t(
        MemoryLayout<task_events_info>.size / MemoryLayout<natural_t>.size)
      let eventsRead = withUnsafeMutablePointer(to: &events) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(eventsCount)) {
          task_info(mach_task_self_, task_flavor_t(TASK_EVENTS_INFO), $0, &eventsCount)
        }
      }
      if eventsRead == KERN_SUCCESS {
        counts[.contextSwitches] = UInt64(UInt32(bitPattern: events.csw))
        counts[.pageFaults] = UInt64(UInt32(bitPattern: events.faults))
        counts[.systemCalls] = UInt64(
          UInt32(bitPattern: events.syscalls_unix) &+ UInt32(bitPattern: events.syscalls_mach))
      }
      #if os(macOS)
        var usage = rusage_info_v4()
        let usageRead = withUnsafeMutablePointer(to: &usage) {
          $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
          }
        }
        if usageRead == 0 {
          counts[.diskReadBytes] = usage.ri_diskio_bytesread
          counts[.diskWriteBytes] = usage.ri_diskio_byteswritten
        }
      #endif
    #elseif os(Linux)
      let usage = ResourceUsage.current()
      counts[.contextSwitches] = UInt64(max(0, usage.ru_nvcsw + usage.ru_nivcsw))
      counts[.pageFaults] = UInt64(max(0, usage.ru_minflt + usage.ru_majflt))
      if let io = processIO() {
        counts[.diskReadBytes] = io.readBytes
        counts[.diskWriteBytes] = io.writeBytes
      }
    #endif
    return counts
  }

  #if os(Linux)
    /// The storage bytes the process read and wrote, from `/proc/self/io`.
    private static func processIO() -> (readBytes: UInt64, writeBytes: UInt64)? {
      guard let file = fopen("/proc/self/io", "r") else {
        return nil
      }
      defer { fclose(file) }
      var readBytes: UInt64?
      var writeBytes: UInt64?
      var buffer = [CChar](repeating: 0, count: 128)
      while fgets(&buffer, Int32(buffer.count), file) != nil {
        let line = String(
          decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let parts = line.split(separator: ":")
        guard parts.count == 2, let value = UInt64(String(parts[1].filter(\.isNumber))) else {
          continue
        }
        switch parts[0] {
        case "read_bytes":
          readBytes = value
        case "write_bytes":
          writeBytes = value
        default:
          break
        }
      }
      guard let readBytes, let writeBytes else {
        return nil
      }
      return (readBytes, writeBytes)
    }
  #endif
}
