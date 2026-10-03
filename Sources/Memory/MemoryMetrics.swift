// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Report

#if canImport(Darwin)
  // Darwin initializes the process task port; this provider only reads it.
  @preconcurrency import Darwin
#endif

public enum MemoryMetricName {
  public static let peakResidentBytes = "memory.peakResidentBytes"
  public static let residentBytes = "memory.residentBytes"
  public static let allocatedBytes = "memory.allocatedBytes"
  public static let deallocatedBytes = "memory.deallocatedBytes"
  public static let netAllocatedBytes = "memory.netAllocatedBytes"
  public static let peakAllocatedBytes = "memory.peakAllocatedBytes"
  public static let allocationCount = "memory.allocationCount"
  public static let deallocationCount = "memory.deallocationCount"
  public static let netAllocationCount = "memory.netAllocationCount"
  public static let leakCount = "memory.leakCount"
  public static let leakedBytes = "memory.leakedBytes"
  public static let fileDescriptorCount = "resource.fileDescriptorCount"
  public static let fileDescriptorLeakCount = "resource.fileDescriptorLeakCount"
}

public protocol MemoryMetricProvider: MetricProvider {}

public struct UnavailableMemoryMetricProvider: MemoryMetricProvider {
  public var requirement: DiagnosticRequirement
  public var reason: String

  public init(
    reason: String = "Memory metrics are unavailable on this platform or process type.",
    requirement: DiagnosticRequirement = .optional
  ) {
    self.reason = reason
    self.requirement = requirement
  }

  public func metrics(for scope: ReportScope) async -> [DiagnosticMetric] {
    [
      DiagnosticMetric(
        id: "metric:memory-peak-resident-bytes",
        scope: scope,
        name: MemoryMetricName.peakResidentBytes,
        state: .unavailable(reason)
      ),
      DiagnosticMetric(
        id: "metric:memory-allocated-bytes",
        scope: scope,
        name: MemoryMetricName.allocatedBytes,
        state: .unavailable(reason)
      ),
      DiagnosticMetric(
        id: "metric:memory-allocation-count",
        scope: scope,
        name: MemoryMetricName.allocationCount,
        state: .unavailable(reason)
      ),
      DiagnosticMetric(
        id: "metric:memory-peak-allocated-bytes",
        scope: scope,
        name: MemoryMetricName.peakAllocatedBytes,
        state: .unavailable(reason)
      ),
    ]
  }
}

public struct ResidentMemoryMetricProvider: MemoryMetricProvider {
  public var requirement: DiagnosticRequirement

  public init(requirement: DiagnosticRequirement = .optional) {
    self.requirement = requirement
  }

  public func metrics(for scope: ReportScope) async -> [DiagnosticMetric] {
    #if canImport(Darwin)
      var info = mach_task_basic_info()
      var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
      )
      let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
          task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
        }
      }
      guard result == KERN_SUCCESS else {
        return [
          DiagnosticMetric(
            id: "metric:memory-resident-bytes",
            scope: scope,
            name: MemoryMetricName.residentBytes,
            state: .failed("task_info failed with status \(result).")
          )
        ]
      }
      let residentBytes = Double(info.resident_size)
      let peakResidentBytes = Double(info.resident_size_max)
      return [
        DiagnosticMetric(
          id: "metric:memory-resident-bytes",
          scope: scope,
          name: MemoryMetricName.residentBytes,
          state: .measured(residentBytes, unit: "bytes")
        ),
        DiagnosticMetric(
          id: "metric:memory-peak-resident-bytes",
          scope: scope,
          name: MemoryMetricName.peakResidentBytes,
          state: .measured(peakResidentBytes, unit: "bytes")
        ),
      ]
    #else
      return await UnavailableMemoryMetricProvider(
        reason: "Resident memory metrics are unavailable on this platform.",
        requirement: requirement
      ).metrics(for: scope)
    #endif
  }
}

public struct ManualMemoryMetricProvider: MemoryMetricProvider {
  public var peakResidentBytes: Double?
  public var allocatedBytes: Double?
  public var allocationCount: Double?
  public var requirement: DiagnosticRequirement

  public init(
    peakResidentBytes: Double? = nil,
    allocatedBytes: Double? = nil,
    allocationCount: Double? = nil,
    requirement: DiagnosticRequirement = .optional
  ) {
    self.peakResidentBytes = peakResidentBytes
    self.allocatedBytes = allocatedBytes
    self.allocationCount = allocationCount
    self.requirement = requirement
  }

  public func metrics(for scope: ReportScope) async -> [DiagnosticMetric] {
    var metrics: [DiagnosticMetric] = []
    if let peakResidentBytes {
      metrics.append(
        DiagnosticMetric(
          id: "metric:memory-peak-resident-bytes",
          scope: scope,
          name: MemoryMetricName.peakResidentBytes,
          state: .measured(peakResidentBytes, unit: "bytes")
        )
      )
    }
    if let allocatedBytes {
      metrics.append(
        DiagnosticMetric(
          id: "metric:memory-allocated-bytes",
          scope: scope,
          name: MemoryMetricName.allocatedBytes,
          state: .measured(allocatedBytes, unit: "bytes")
        )
      )
    }
    if let allocationCount {
      metrics.append(
        DiagnosticMetric(
          id: "metric:memory-allocation-count",
          scope: scope,
          name: MemoryMetricName.allocationCount,
          state: .measured(allocationCount, unit: "count")
        )
      )
    }
    if metrics.isEmpty {
      metrics.append(
        DiagnosticMetric(
          id: "metric:memory",
          scope: scope,
          name: "memory",
          state: .notConfigured("No manual memory metrics were provided.")
        )
      )
    }
    return metrics
  }
}

public struct AllocationMetricSnapshot: Sendable, Equatable {
  public var allocatedBytes: Double
  public var deallocatedBytes: Double
  public var allocationCount: Double
  public var deallocationCount: Double
  public var peakAllocatedBytes: Double
  public var leakedBytes: Double
  public var leakCount: Double

  public init(
    allocatedBytes: Double,
    deallocatedBytes: Double,
    allocationCount: Double,
    deallocationCount: Double,
    peakAllocatedBytes: Double,
    leakedBytes: Double = 0,
    leakCount: Double = 0
  ) {
    self.allocatedBytes = allocatedBytes
    self.deallocatedBytes = deallocatedBytes
    self.allocationCount = allocationCount
    self.deallocationCount = deallocationCount
    self.peakAllocatedBytes = peakAllocatedBytes
    self.leakedBytes = leakedBytes
    self.leakCount = leakCount
  }

  public var netAllocatedBytes: Double {
    allocatedBytes - deallocatedBytes
  }

  public var netAllocationCount: Double {
    allocationCount - deallocationCount
  }
}

public struct ManualAllocationMetricProvider: MemoryMetricProvider {
  public var snapshot: AllocationMetricSnapshot
  public var leakCountTolerance: Double
  public var leakedBytesTolerance: Double
  public var requirement: DiagnosticRequirement

  public init(
    snapshot: AllocationMetricSnapshot,
    leakCountTolerance: Double = 0,
    leakedBytesTolerance: Double = 0,
    requirement: DiagnosticRequirement = .optional
  ) {
    self.snapshot = snapshot
    self.leakCountTolerance = leakCountTolerance
    self.leakedBytesTolerance = leakedBytesTolerance
    self.requirement = requirement
  }

  public func metrics(for scope: ReportScope) async -> [DiagnosticMetric] {
    [
      measuredMetric(
        id: "metric:memory-allocated-bytes",
        scope: scope,
        name: MemoryMetricName.allocatedBytes,
        value: snapshot.allocatedBytes,
        unit: "bytes"
      ),
      measuredMetric(
        id: "metric:memory-deallocated-bytes",
        scope: scope,
        name: MemoryMetricName.deallocatedBytes,
        value: snapshot.deallocatedBytes,
        unit: "bytes"
      ),
      measuredMetric(
        id: "metric:memory-net-allocated-bytes",
        scope: scope,
        name: MemoryMetricName.netAllocatedBytes,
        value: snapshot.netAllocatedBytes,
        unit: "bytes"
      ),
      measuredMetric(
        id: "metric:memory-peak-allocated-bytes",
        scope: scope,
        name: MemoryMetricName.peakAllocatedBytes,
        value: snapshot.peakAllocatedBytes,
        unit: "bytes"
      ),
      measuredMetric(
        id: "metric:memory-allocation-count",
        scope: scope,
        name: MemoryMetricName.allocationCount,
        value: snapshot.allocationCount,
        unit: "count"
      ),
      measuredMetric(
        id: "metric:memory-deallocation-count",
        scope: scope,
        name: MemoryMetricName.deallocationCount,
        value: snapshot.deallocationCount,
        unit: "count"
      ),
      measuredMetric(
        id: "metric:memory-net-allocation-count",
        scope: scope,
        name: MemoryMetricName.netAllocationCount,
        value: snapshot.netAllocationCount,
        unit: "count"
      ),
      leakMetric(
        id: "metric:memory-leak-count",
        scope: scope,
        name: MemoryMetricName.leakCount,
        value: snapshot.leakCount,
        tolerance: leakCountTolerance,
        unit: "count"
      ),
      leakMetric(
        id: "metric:memory-leaked-bytes",
        scope: scope,
        name: MemoryMetricName.leakedBytes,
        value: snapshot.leakedBytes,
        tolerance: leakedBytesTolerance,
        unit: "bytes"
      ),
    ]
  }

  private func measuredMetric(
    id: ReportID,
    scope: ReportScope,
    name: String,
    value: Double,
    unit: String
  ) -> DiagnosticMetric {
    DiagnosticMetric(id: id, scope: scope, name: name, state: .measured(value, unit: unit))
  }

  private func leakMetric(
    id: ReportID,
    scope: ReportScope,
    name: String,
    value: Double,
    tolerance: Double,
    unit: String
  ) -> DiagnosticMetric {
    if value > tolerance {
      return DiagnosticMetric(
        id: id,
        scope: scope,
        name: name,
        state: .failed("\(name) value \(value) exceeded tolerance \(tolerance).")
      )
    }
    return measuredMetric(id: id, scope: scope, name: name, value: value, unit: unit)
  }
}

public enum AllocationAggregation: Sendable, Equatable {
  case min
  case median
}

public struct AllocationRegressionPolicy: Sendable, Equatable {
  public var preheatIterations: Int
  public var measuredIterations: Int
  public var aggregation: AllocationAggregation
  public var leakCountTolerance: Double
  public var leakedBytesTolerance: Double

  public init(
    preheatIterations: Int = 1,
    measuredIterations: Int = 5,
    aggregation: AllocationAggregation = .median,
    leakCountTolerance: Double = 0,
    leakedBytesTolerance: Double = 0
  ) {
    self.preheatIterations = preheatIterations
    self.measuredIterations = measuredIterations
    self.aggregation = aggregation
    self.leakCountTolerance = leakCountTolerance
    self.leakedBytesTolerance = leakedBytesTolerance
  }

  public func validate() throws {
    guard preheatIterations >= 0 else {
      throw AllocationRegressionError.invalidPolicy("preheatIterations must be nonnegative.")
    }
    guard measuredIterations > 0 else {
      throw AllocationRegressionError.invalidPolicy("measuredIterations must be positive.")
    }
  }
}

public enum AllocationRegressionError: Error, CustomStringConvertible {
  case invalidPolicy(String)
  case insufficientSamples(expected: Int, actual: Int)

  public var description: String {
    switch self {
    case .invalidPolicy(let message):
      return message
    case .insufficientSamples(let expected, let actual):
      return "Expected at least \(expected) allocation samples, got \(actual)."
    }
  }
}

public struct AllocationRegressionSummary: Sendable, Equatable {
  public var policy: AllocationRegressionPolicy
  public var measuredSamples: [AllocationMetricSnapshot]
  public var selected: AllocationMetricSnapshot

  public var remainingAllocationCount: Double {
    selected.netAllocationCount
  }

  public var remainingAllocatedBytes: Double {
    selected.netAllocatedBytes
  }

  public func metrics(for scope: ReportScope) async -> [DiagnosticMetric] {
    await ManualAllocationMetricProvider(
      snapshot: selected,
      leakCountTolerance: policy.leakCountTolerance,
      leakedBytesTolerance: policy.leakedBytesTolerance
    ).metrics(for: scope)
  }
}

public struct AllocationRegressionAnalyzer: Sendable {
  public var policy: AllocationRegressionPolicy

  public init(policy: AllocationRegressionPolicy = AllocationRegressionPolicy()) {
    self.policy = policy
  }

  public func summarize(_ samples: [AllocationMetricSnapshot]) throws -> AllocationRegressionSummary
  {
    try policy.validate()
    let expected = policy.preheatIterations + policy.measuredIterations
    guard samples.count >= expected else {
      throw AllocationRegressionError.insufficientSamples(expected: expected, actual: samples.count)
    }
    let measured = Array(
      samples.dropFirst(policy.preheatIterations).prefix(policy.measuredIterations))
    return AllocationRegressionSummary(
      policy: policy,
      measuredSamples: measured,
      selected: AllocationMetricSnapshot(
        allocatedBytes: aggregate(measured.map(\.allocatedBytes)),
        deallocatedBytes: aggregate(measured.map(\.deallocatedBytes)),
        allocationCount: aggregate(measured.map(\.allocationCount)),
        deallocationCount: aggregate(measured.map(\.deallocationCount)),
        peakAllocatedBytes: aggregate(measured.map(\.peakAllocatedBytes)),
        leakedBytes: aggregate(measured.map(\.leakedBytes)),
        leakCount: aggregate(measured.map(\.leakCount))
      )
    )
  }

  private func aggregate(_ values: [Double]) -> Double {
    let values = values.sorted()
    guard !values.isEmpty else {
      return 0
    }
    switch policy.aggregation {
    case .min:
      return values[0]
    case .median:
      let middle = values.count / 2
      if values.count.isMultiple(of: 2) {
        return (values[middle - 1] + values[middle]) / 2
      }
      return values[middle]
    }
  }
}

public struct FileDescriptorSnapshot: Sendable, Equatable {
  public var openFileDescriptorCount: Int

  public init(openFileDescriptorCount: Int) {
    self.openFileDescriptorCount = openFileDescriptorCount
  }
}

public struct FileDescriptorLeakCheck: Sendable, Equatable {
  public var before: FileDescriptorSnapshot
  public var after: FileDescriptorSnapshot
  public var tolerance: Int

  public init(
    before: FileDescriptorSnapshot,
    after: FileDescriptorSnapshot,
    tolerance: Int = 0
  ) {
    self.before = before
    self.after = after
    self.tolerance = tolerance
  }

  public var leakedFileDescriptorCount: Int {
    max(0, after.openFileDescriptorCount - before.openFileDescriptorCount)
  }

  public func metrics(for scope: ReportScope) -> [DiagnosticMetric] {
    let leakState: DiagnosticState =
      leakedFileDescriptorCount > tolerance
      ? .failed(
        "file descriptor leak count \(leakedFileDescriptorCount) exceeded tolerance \(tolerance)."
      )
      : .measured(Double(leakedFileDescriptorCount), unit: "count")
    return [
      DiagnosticMetric(
        id: "metric:resource-file-descriptor-count",
        scope: scope,
        name: MemoryMetricName.fileDescriptorCount,
        state: .measured(Double(after.openFileDescriptorCount), unit: "count")
      ),
      DiagnosticMetric(
        id: "metric:resource-file-descriptor-leak-count",
        scope: scope,
        name: MemoryMetricName.fileDescriptorLeakCount,
        state: leakState
      ),
    ]
  }
}
