// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

@BenchmarkSuite("Host", .tag("macro-host"))
struct HostBenchmarks {
  @Benchmark("Measured", .tag("fast"))
  func measured() {
    blackHole(1)
  }

  @Benchmark("Sized", .dimension(sizes: [1, 2]))
  func sized(_ size: Benchmark.Scale) {
    blackHole(size.rawValue)
  }
}

@BenchmarkSuite("HostCheck")
struct HostCheckBenchmarks {
  @Benchmark("Slow first invocation")
  func slowFirstInvocation() {
    HostCheckWorkload.shared.invoke()
  }
}

@Suite("Benchmark Host", .serialized)
struct BenchmarkHostTests {
  @Test
  func listPlansStepsWithTheirIdentifiersAndMetadata() async throws {
    let plan = try await hostPlan(["list"])
    let filtered = try await hostPlan(["list", "--tag", "fast"])

    #expect(plan.metadata == .fixture())
    #expect(plan.steps.map(\.caseName) == ["Measured", "Sized", "Sized"])
    #expect(plan.steps.map(\.dimensionSizes) == [[], [1], [2]])
    #expect(Set(plan.steps.map(\.id)).count == 3)
    #expect(filtered.steps.map(\.caseName) == ["Measured"])
    #expect(filtered.steps.first?.tags == ["macro-host", "fast"])
  }

  @Test
  func measureRunsOnlyTheSelectedStepsWithConfigurationOverrides() async throws {
    let step = try #require(try await hostPlan(["list"]).steps.last)

    let measurement = try await hostMeasurement([
      "measure", "--step", step.id, "--warmup", "0", "--batch-size", "1", "--iterations", "2",
    ])
    let document = try #require(
      try await BenchmarkCommand.document(measurements: [measurement]))
    let report = try #require(document.suites.first?.cases.first)

    #expect(document.metadata == .fixture())
    #expect(report.name == "Sized")
    #expect(report.measurement.rows.map(\.size) == [Benchmark.Scale(2)])
    #expect(report.samples.filter { $0.value(for: .wallClock) != nil }.count == 2)
    #expect(report.samples.allSatisfy { $0.batchSize == 1 })
    #expect(report.configuration.warmup == "none")
    #expect(report.configuration.iterations == "iterations(2)")
    #expect(report.configuration.batching == "fixed(1)")
  }

  @Test
  func stepsMeasuredSeparatelyReportLikeOneRun() async throws {
    let steps = try await hostPlan(["list"]).steps
    let overrides = ["--warmup", "0", "--batch-size", "1", "--iterations", "2"]

    var separate: [HostMeasurement] = []
    for step in steps {
      separate.append(try await hostMeasurement(["measure", "--step", step.id] + overrides))
    }
    let together = try await hostMeasurement(["measure"] + overrides)
    let separateReport = try #require(try await BenchmarkCommand.document(measurements: separate))
    let togetherReport = try #require(try await BenchmarkCommand.document(measurements: [together]))

    func shape(_ document: ReportDocument) -> [String] {
      document.suites.flatMap(\.cases).flatMap { report in
        report.measurement.rows.map { row in
          "\(report.name) \(row.size?.rawValue ?? 0) \(row.samples.count) \(row.metrics.map(\.name))"
        }
      }
    }
    #expect(shape(separateReport) == shape(togetherReport))
    #expect(shape(separateReport).count == 3)
  }

  @Test
  func reportsCompareTheMeasurementTheyContain() async throws {
    let baseline = BaselineDocument(cases: [
      BaselineCase(
        suiteName: "HostCheck",
        caseName: "Slow first invocation",
        measurement: Report.Measurement(
          samples: [
            SampleReport(
              id: "sample:hostcheck.0", iterationID: "iteration:hostcheck.0", iteration: 0,
              values: ["wallClock": 1_000_000])
          ],
          metrics: [.wallClock]
        )
      )
    ])
    HostCheckWorkload.shared.reset()

    let measurement = try await HostMeasurement.decode(
      BenchmarkHost.output(
        discoveries: [HostCheckBenchmarks.self],
        arguments: ["measure", "--warmup", "0", "--batch-size", "1", "--iterations", "1"],
        metadata: .fixture()
      ))
    let document = try #require(
      try await BenchmarkCommand.document(
        measurements: [measurement],
        baseline: baseline,
        comparison: ComparisonArguments.policy(
          statistic: nil, thresholds: ["wallClock=10ms"], budgets: [], caseBudgets: [])
      ))

    #expect(document.summary.verdict == .failed)
    #expect(document.summary.failedRegressionCount == 1)
    // One timed call produced the reported verdict; the second call is the
    // allocation counting pass, which records no time.
    #expect(HostCheckWorkload.shared.invocationCount == 2)
  }

  @Test
  func reportsAttachTracesToEveryCase() async throws {
    let tracePath = FileManager.default.temporaryDirectory
      .appendingPathComponent("benchmark-host-\(UUID().uuidString).trace")
      .path
    try FileManager.default.createDirectory(atPath: tracePath, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tracePath) }
    let measurement = try await hostMeasurement([
      "measure", "--tag", "fast", "--warmup", "0", "--batch-size", "1", "--iterations", "1",
    ])

    let document = try #require(
      try await BenchmarkCommand.document(
        measurements: [measurement],
        traceExporters: [
          TraceArtifactExporter(
            artifact: TraceArtifact(
              tracePath: tracePath,
              command: ["xcrun xctrace record"],
              metadata: ["tool": "xctrace", "template": "Time Profiler"]
            )
          )
        ]
      ))
    let report = try #require(document.suites.first?.cases.first)
    let attachment = try #require(report.attachments.first)

    #expect(attachment.kind == .trace)
    #expect(attachment.location == tracePath)
    #expect(attachment.metadata["tool"] == "xctrace")
    #expect(attachment.metadata["template"] == "Time Profiler")
    #expect(attachment.metadata["command"] == "xcrun xctrace record")
  }

  @Test
  func unknownStepsAndArgumentsAreRejected() async throws {
    await #expect(throws: BenchmarkHostError.self) {
      try await hostMeasurement(["measure", "--step", "benchmark:missing"])
    }
    await #expect(throws: BenchmarkHostError.self) {
      try await hostMeasurement(["measure", "--baseline", "baseline.json"])
    }
  }

  @Test
  func anIsolatedMeasurementMeasuresExactlyOneStep() async throws {
    let plan = try await hostPlan(["list", "--case", "Sized"])
    let sized = plan.steps.map(\.id)

    #expect(sized.count == 2)
    await #expect(throws: BenchmarkHostError.self) {
      try await hostMeasurement(
        ["measure", "--isolated", "--warmup", "0", "--iterations", "1"]
          + sized.flatMap { ["--step", $0] })
    }
    let isolated = try await hostMeasurement(
      ["measure", "--isolated", "--warmup", "0", "--iterations", "1", "--step", sized[0]])
    #expect(isolated.records.contains { $0.kind == .sampleRecorded })
  }

  private func hostPlan(_ arguments: [String]) async throws -> HostPlan {
    try JSONDecoder().decode(
      HostPlan.self,
      from: await BenchmarkHost.output(
        discoveries: [HostBenchmarks.self], arguments: arguments, metadata: .fixture()))
  }

  private func hostMeasurement(_ arguments: [String]) async throws -> HostMeasurement {
    try HostMeasurement.decode(
      await BenchmarkHost.output(
        discoveries: [HostBenchmarks.self], arguments: arguments, metadata: .fixture()))
  }
}

extension HostMeasurement {
  fileprivate static func decode(_ data: Data) throws -> HostMeasurement {
    try JSONDecoder().decode(HostMeasurement.self, from: data)
  }
}

private final class HostCheckWorkload: @unchecked Sendable {
  static let shared = HostCheckWorkload()

  private let lock = NSLock()
  private var invocations = 0

  var invocationCount: Int {
    lock.withLock { invocations }
  }

  func reset() {
    lock.withLock { invocations = 0 }
  }

  func invoke() {
    let isFirstInvocation = lock.withLock {
      invocations += 1
      return invocations == 1
    }
    if isFirstInvocation {
      Thread.sleep(forTimeInterval: 0.05)
    }
  }
}
