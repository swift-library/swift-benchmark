// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Memory
import Report
import Testing

@Suite("Memory Metrics")
struct MemoryTests {
  @Test
  func unavailableMemoryProviderDoesNotFakeZeroMetrics() async {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let metrics = await UnavailableMemoryMetricProvider(reason: "unsupported").metrics(for: scope)

    #expect(metrics.count == 4)
    #expect(metrics.allSatisfy { $0.state.kind == .unavailable })
    #expect(metrics.allSatisfy { $0.state.value == nil })
    #expect(metrics.allSatisfy { $0.state.reason == "unsupported" })
  }

  @Test
  func manualMemoryProviderReportsMeasuredValues() async {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let metrics = await ManualMemoryMetricProvider(
      peakResidentBytes: 4096,
      allocatedBytes: 2048,
      allocationCount: 12
    ).metrics(for: scope)

    #expect(metrics.map(\.state.kind) == [.measured, .measured, .measured])
    #expect(metrics.map(\.state.value) == [4096, 2048, 12])
  }

  @Test
  func residentMemoryProviderReportsMeasuredOrUnavailableState() async throws {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let metrics = await ResidentMemoryMetricProvider().metrics(for: scope)

    #if canImport(Darwin)
      #expect(
        metrics.map(\.name) == [
          MemoryMetricName.residentBytes,
          MemoryMetricName.peakResidentBytes,
        ])
      #expect(metrics.allSatisfy { $0.state.kind == .measured })
      #expect(metrics.allSatisfy { ($0.state.value ?? 0) > 0 })
      let resident = try #require(
        metrics.first { $0.name == MemoryMetricName.residentBytes }?.state.value)
      let peak = try #require(
        metrics.first { $0.name == MemoryMetricName.peakResidentBytes }?.state.value)
      #expect(peak >= resident)
    #else
      #expect(metrics.allSatisfy { $0.state.kind == .unavailable })
    #endif
  }

  @Test
  func manualAllocationProviderReportsNetPeakAndLeakToleranceMetrics() async {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let metrics = await ManualAllocationMetricProvider(
      snapshot: AllocationMetricSnapshot(
        allocatedBytes: 4096,
        deallocatedBytes: 1024,
        allocationCount: 10,
        deallocationCount: 4,
        peakAllocatedBytes: 5000,
        leakedBytes: 0,
        leakCount: 0
      )
    ).metrics(for: scope)

    #expect(
      metrics.map(\.name) == [
        MemoryMetricName.allocatedBytes,
        MemoryMetricName.deallocatedBytes,
        MemoryMetricName.netAllocatedBytes,
        MemoryMetricName.peakAllocatedBytes,
        MemoryMetricName.allocationCount,
        MemoryMetricName.deallocationCount,
        MemoryMetricName.netAllocationCount,
        MemoryMetricName.leakCount,
        MemoryMetricName.leakedBytes,
      ])
    #expect(metrics.map(\.state.kind).allSatisfy { $0 == .measured })
    #expect(metrics[2].state.value == 3072)
    #expect(metrics[6].state.value == 6)
  }

  @Test
  func manualAllocationProviderFailsLeaksAboveTolerance() async {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let metrics = await ManualAllocationMetricProvider(
      snapshot: AllocationMetricSnapshot(
        allocatedBytes: 4096,
        deallocatedBytes: 1024,
        allocationCount: 10,
        deallocationCount: 4,
        peakAllocatedBytes: 5000,
        leakedBytes: 256,
        leakCount: 2
      ),
      leakCountTolerance: 0,
      leakedBytesTolerance: 128
    ).metrics(for: scope)

    #expect(metrics.first { $0.name == MemoryMetricName.leakCount }?.state.kind == .failed)
    #expect(metrics.first { $0.name == MemoryMetricName.leakedBytes }?.state.kind == .failed)
  }

  @Test
  func allocationRegressionAnalyzerDropsPreheatAndAggregatesMeasuredRuns() async throws {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let analyzer = AllocationRegressionAnalyzer(
      policy: AllocationRegressionPolicy(
        preheatIterations: 1,
        measuredIterations: 3,
        aggregation: .median,
        leakCountTolerance: 0,
        leakedBytesTolerance: 64
      )
    )
    let summary = try analyzer.summarize([
      AllocationMetricSnapshot(
        allocatedBytes: 9_999,
        deallocatedBytes: 0,
        allocationCount: 99,
        deallocationCount: 0,
        peakAllocatedBytes: 9_999
      ),
      AllocationMetricSnapshot(
        allocatedBytes: 1_000,
        deallocatedBytes: 900,
        allocationCount: 10,
        deallocationCount: 9,
        peakAllocatedBytes: 1_100,
        leakedBytes: 0,
        leakCount: 0
      ),
      AllocationMetricSnapshot(
        allocatedBytes: 1_200,
        deallocatedBytes: 1_000,
        allocationCount: 12,
        deallocationCount: 10,
        peakAllocatedBytes: 1_300,
        leakedBytes: 256,
        leakCount: 1
      ),
      AllocationMetricSnapshot(
        allocatedBytes: 800,
        deallocatedBytes: 700,
        allocationCount: 8,
        deallocationCount: 7,
        peakAllocatedBytes: 900,
        leakedBytes: 128,
        leakCount: 0
      ),
    ])
    let metrics = await summary.metrics(for: scope)

    #expect(summary.measuredSamples.count == 3)
    #expect(summary.selected.allocatedBytes == 1_000)
    #expect(summary.remainingAllocationCount == 1)
    #expect(metrics.first { $0.name == MemoryMetricName.leakedBytes }?.state.kind == .failed)
  }

  @Test
  func fileDescriptorLeakCheckReportsMeasuredAndFailedStates() {
    let scope = ReportScope(
      runID: "run:memory", suiteID: "suite:parser", caseID: "case:parser.parse")
    let passing = FileDescriptorLeakCheck(
      before: FileDescriptorSnapshot(openFileDescriptorCount: 4),
      after: FileDescriptorSnapshot(openFileDescriptorCount: 5),
      tolerance: 1
    ).metrics(for: scope)
    let failing = FileDescriptorLeakCheck(
      before: FileDescriptorSnapshot(openFileDescriptorCount: 4),
      after: FileDescriptorSnapshot(openFileDescriptorCount: 7),
      tolerance: 1
    ).metrics(for: scope)

    #expect(
      passing.first { $0.name == MemoryMetricName.fileDescriptorLeakCount }?.state.kind == .measured
    )
    #expect(
      failing.first { $0.name == MemoryMetricName.fileDescriptorLeakCount }?.state.kind == .failed)
    #expect(failing.first { $0.name == MemoryMetricName.fileDescriptorCount }?.state.value == 7)
  }
}
