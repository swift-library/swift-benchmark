// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import BenchmarkTesting
import BenchmarkXCTest
import Foundation
import Report
import Testing

@Suite("Testing Adapters")
struct AdapterTests {
  @Test
  func successfulAdaptersPreserveArgumentSamplesAndAttachmentSummary() async throws {
    let suite = BenchmarkSuite(
      "Adapters",
      configuration: .init(warmup: .iterations(1), iterations: .iterations(3))
    ) {
      Benchmark("Arguments", arguments: [1, 2]) { value in
        blackHole(value)
      }
    }
    let adapter = BenchmarkTestingAdapter(
      command: BenchmarkCommand(
        runner: BenchmarkRunner(clock: StepClock(step: 10), cpuClock: nil, countsAllocations: false)
      ))

    let document = try await adapter.report(
      suites: [suite], metadata: .local(id: "run:adapter", packageIdentity: "swift-benchmark"))
    let report = try #require(document.suites.first?.cases.first)
    let payload = try #require(
      BenchmarkXCTestAdapter().reportAttachmentPayloads(for: document).first)
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: Data(payload.content.utf8))

    #expect(report.measurement.rows.count == 2)
    #expect(report.measurement.rows.allSatisfy { $0.samples.count == 3 })
    #expect(adapter.failureSummary(for: document) == nil)
    #expect(decoded.summary == document.summary)
  }

  @Test
  func testingAndXCTestAdaptersUseReportVerdicts() async throws {
    let metadata = RunMetadata(
      id: "run:adapter",
      swiftVersion: "6.3.1",
      packageIdentity: "swift-benchmark",
      platform: "macOS",
      architecture: "arm64",
      osVersion: "15",
      generatedAt: "2026-05-11T00:00:00Z",
      buildConfiguration: "debug"
    )
    let suite = BenchmarkSuite(
      "Adapters",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Parse") {
        blackHole(1)
      }
    }
    let baseline = BaselineDocument(cases: [
      BaselineCase(
        suiteName: "Adapters",
        caseName: "Parse",
        measurement: Report.Measurement(
          samples: [
            SampleReport(
              id: "sample:adapters.parse.0", iterationID: "iteration:adapters.parse.0",
              iteration: 0, values: ["wallClock": 1])
          ],
          metrics: [.wallClock]
        )
      )
    ])
    let command = BenchmarkCommand(
      runner: BenchmarkRunner(clock: StepClock(step: 10), cpuClock: nil, countsAllocations: false))
    let testingAdapter = BenchmarkTestingAdapter(command: command)
    let xctestAdapter = BenchmarkXCTestAdapter(command: command)

    let document = try await testingAdapter.report(
      suites: [suite],
      metadata: metadata,
      baseline: baseline,
      comparison: ComparisonPolicy(budgets: [
        BudgetPolicy(metric: .wallClock, statistic: .mean, limit: 1)
      ])
    )
    let testingContexts = testingAdapter.failureContexts(for: document)
    let xctestContexts = xctestAdapter.failureContexts(for: document)
    let attachmentPayloads = try xctestAdapter.reportAttachmentPayloads(for: document)

    #expect(testingAdapter.failureSummary(for: document)?.contains("1 regression") == true)
    #expect(testingAdapter.failureSummary(for: document)?.contains("1 budget failure") == true)
    #expect(xctestAdapter.failureSummary(for: document)?.contains("1 regression") == true)
    #expect(testingContexts.map(\.suiteName) == ["Adapters", "Adapters"])
    #expect(testingContexts.map(\.caseName) == ["Parse", "Parse"])
    #expect(testingContexts.map(\.cause.kind) == [.baselineRegression, .budgetExceeded])
    #expect(
      testingContexts.allSatisfy { $0.sourceLocation?.fileID.contains("AdapterTests") == true })
    #expect(xctestContexts.map(\.message) == testingContexts.map(\.message))
    #expect(attachmentPayloads.first?.uniformTypeIdentifier == "public.json")
    #expect(attachmentPayloads.first?.content.contains("\"verdictCauses\"") == true)
  }

  @Test
  func swiftTestingBenchmarkTraitCarriesReportPolicy() {
    let testTrait: any TestTrait = .benchmark(
      comparison: ComparisonPolicy(
        statistic: .p95,
        budgets: [BudgetPolicy(metric: .wallClock, statistic: .p95, limit: 100)]
      )
    )
    let suiteTrait: any SuiteTrait = .benchmark(
      comparison: ComparisonPolicy(
        metricThresholds: [.wallClock: .absolute(50)],
        budgets: [BudgetPolicy(metric: .wallClock, statistic: .mean, limit: 200)]
      )
    )

    #expect((testTrait as? BenchmarkTestingTrait)?.comparison.statistic == .p95)
    #expect((testTrait as? BenchmarkTestingTrait)?.comparison.budgets.first?.statistic == .p95)
    #expect(
      (suiteTrait as? BenchmarkTestingTrait)?.comparison.threshold(for: .wallClock)
        == .absolute(50))
    #expect((suiteTrait as? BenchmarkTestingTrait)?.comparison.budgets.first?.limit == 200)
  }
}

private struct StepClock: BenchmarkClock {
  var step: UInt64
  private let state = StepClockState()

  func now() -> BenchmarkInstant {
    state.next(step: step)
  }
}

private final class StepClockState: @unchecked Sendable {
  private var value: UInt64 = 0

  func next(step: UInt64) -> BenchmarkInstant {
    defer {
      value += step
    }
    return BenchmarkInstant(nanoseconds: value)
  }
}
