// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Benchmark
import BenchmarkTesting
import BenchmarkXCTest
import Foundation
import Instruments
import Memory
import ReleaseConsumer
import Report
import Testing

@Suite("Release Runtime")
struct ConsumerTests {
  @Test
  func externalMacrosPreserveValuesAndNestedInstrumentation() {
    let recorder = InMemoryRecorder()
    let value = Instruments.withCurrentRecorder(recorder) {
      ReleaseWorkload().evaluate(21)
    }
    let timeline = recorder.snapshot()
    #expect(value == 42)
    #expect(timeline.spans.count == 3)
    #expect(timeline.spans.allSatisfy { $0.end != nil })
    let nested = timeline.spans.first { $0.name == "consumer.nested" }
    #expect(nested?.parentID != nil)
    #expect(timeline.events.first?.parentSpanID == nested?.id)
  }

  @Test
  func externalRunnerAndAdaptersProduceUsableReports() async throws {
    let suite = BenchmarkSuite(
      "Consumer",
      configuration: .init(warmup: .iterations(1), iterations: .iterations(3))
    ) {
      Benchmark("Arguments", arguments: [1, 2]) { value in
        blackHole(ReleaseWorkload().evaluate(value))
      }
    }
    let adapter = BenchmarkTestingAdapter()
    let document = try await adapter.report(
      suites: [suite], metadata: .local(id: "run:consumer", packageIdentity: "ReleaseConsumer")
    )
    let report = try #require(document.suites.first?.cases.first)
    #expect(report.measurement.rows.count == 2)
    #expect(report.measurement.rows.allSatisfy { $0.samples.count == 3 })
    #expect(adapter.failureSummary(for: document) == nil)
    let payload = try #require(
      BenchmarkXCTestAdapter().reportAttachmentPayloads(for: document).first)
    let decoded = try JSONDecoder().decode(ReportDocument.self, from: Data(payload.content.utf8))
    #expect(decoded.summary == document.summary)
    let scope = ReportScope(runID: "run:consumer")
    let metrics = await ResidentMemoryMetricProvider().metrics(for: scope)
    #expect(metrics.allSatisfy { $0.state.kind == .measured && ($0.state.value ?? 0) > 0 })
  }
}

@Suite(
  "ReleaseTesting",
  .benchmark(configuration: .init(warmup: .iterations(1), iterations: .iterations(3)))
)
struct TestingBenchmarks {
  @Test("Argument Workload", arguments: [1, 2])
  func workload(_ value: Int) {
    blackHole(ReleaseWorkload().evaluate(value))
  }
}
