// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Instruments
import Report
import Testing

@BenchmarkSuite("Merged")
struct MergedBenchmarks {
  @Benchmark("First")
  func first() {
    blackHole(1)
  }

  @Benchmark("Second")
  func second() {
    blackHole(2)
  }
}

@Suite("Benchmark Command", .serialized)
struct BenchmarkCommandTests {
  @Test
  func commandRunsSuitesThroughBenchmarkAndReport() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let document = try await BenchmarkCommand(
      runner: BenchmarkRunner(clock: StepClock(step: 100), cpuClock: nil, countsAllocations: false)
    )
    .report(
      plan: BenchmarkRunner.Plan(suites: [suite]),
      metadata: .fixture()
    )
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.name == "Measured")
    #expect(report.samples.map { $0.value(for: .wallClock) } == [100, 100])
    #expect(document.summary.caseCount == 1)
  }

  @Test
  func mergedMeasurementsScopeEveryAttributionToTheReportsRun() async throws {
    var measurements: [HostMeasurement] = []
    for (index, caseName) in ["First", "Second"].enumerated() {
      var metadata = RunMetadata.fixture()
      metadata.id = ReportID(rawValue: "run:\(index)")
      let output = try await BenchmarkHost.output(
        discoveries: [MergedBenchmarks.self],
        arguments: [
          "measure", "--timeline", "--case", caseName, "--warmup", "0", "--iterations", "1",
          "--batch-size", "1",
        ],
        metadata: metadata
      )
      measurements.append(try JSONDecoder().decode(HostMeasurement.self, from: output))
    }

    let document = try #require(try await BenchmarkCommand.document(measurements: measurements))
    let cases = document.suites.flatMap(\.cases)

    #expect(document.metadata.id == "run:0")
    #expect(cases.count == 2)
    #expect(cases.allSatisfy { !$0.attributions.isEmpty })
    #expect(cases.flatMap(\.attributions).allSatisfy { $0.scope.runID == "run:0" })
  }

  @Test
  func commandCanCaptureBenchmarkIterationTimelineAttribution() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(2), batching: .fixed(1))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let document = try await BenchmarkCommand(
      runner: BenchmarkRunner(clock: StepClock(step: 100), cpuClock: nil, countsAllocations: false)
    )
    .report(
      plan: BenchmarkRunner.Plan(suites: [suite]),
      metadata: .fixture(),
      timelineCapture: .benchmarkIterations
    )
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.attributions.count == 2)
    #expect(
      report.attributions.map { $0.scope.sampleID?.rawValue } == [
        "sample:Command.Measured.0",
        "sample:Command.Measured.1",
      ])
    #expect(
      report.attributions.allSatisfy { attribution in
        attribution.spans.map(\.name) == ["BenchmarkIteration"]
          && attribution.events.map(\.name) == ["BenchmarkIterationMeasured"]
          && attribution.spanSummaries.map(\.name) == ["BenchmarkIteration"]
      })
  }

  @Test
  func commandCapturesWorkloadSpansAsTimelineDescendants() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Measured") {
        Instruments.current.span("Parser.normalize") {
          Instruments.current.event("Parser.cacheHit")
          blackHole(1)
        }
      }
    }
    let document = try await BenchmarkCommand(
      runner: BenchmarkRunner(clock: StepClock(step: 100), cpuClock: nil, countsAllocations: false)
    )
    .report(
      plan: BenchmarkRunner.Plan(suites: [suite]),
      metadata: .fixture(),
      timelineCapture: .benchmarkIterations
    )
    let report = try #require(document.suites.first?.cases.first)
    let attribution = try #require(report.attributions.first)

    #expect(attribution.spans.map(\.name) == ["BenchmarkIteration", "Parser.normalize"])
    #expect(attribution.events.map(\.name) == ["Parser.cacheHit", "BenchmarkIterationMeasured"])
    #expect(attribution.events.first?.parentSpanID == attribution.spans[1].id)
    #expect(attribution.spanSummaries.map(\.name) == ["BenchmarkIteration", "Parser.normalize"])
  }

  @Test
  func commandRestoresCurrentRecorderWhenTimelineWorkloadThrows() async throws {
    enum DummyError: Error, Equatable {
      case boom
    }

    let previous = IdentityRecorder()
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Throws") {
        throw DummyError.boom
      }
    }

    await Instruments.withCurrentRecorder(previous) {
      do {
        _ = try await BenchmarkCommand(
          runner: BenchmarkRunner(
            clock: StepClock(step: 100), cpuClock: nil, countsAllocations: false)
        ).report(
          plan: BenchmarkRunner.Plan(suites: [suite]),
          metadata: .fixture(),
          timelineCapture: .benchmarkIterations
        )
        Issue.record("Expected throwing benchmark to fail")
      } catch {
        #expect((Instruments.current as? IdentityRecorder) === previous)
      }
    }
  }

  @Test
  func commandFailsWhenRequiredTraceArtifactIsUnavailable() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(
        warmup: .none, iterations: .iterations(1), batching: .fixed(1))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }

    do {
      _ = try await BenchmarkCommand(
        runner: BenchmarkRunner(
          clock: StepClock(step: 100), cpuClock: nil, countsAllocations: false)
      ).report(
        plan: BenchmarkRunner.Plan(suites: [suite]),
        metadata: .fixture(),
        traceExporters: [
          TraceArtifactExporter(
            artifact: TraceArtifact(tracePath: "/tmp/missing.trace"),
            requirement: .required,
            fileExists: { _ in false }
          )
        ]
      )
      Issue.record("Expected required missing trace artifact to fail")
    } catch let error as BenchmarkCommandError {
      #expect(error.description.contains("Required diagnostic attachment"))
    }
  }
}

private final class IdentityRecorder: Recorder, @unchecked Sendable {
  func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken {
    .empty
  }

  func endSpan(_ token: SpanToken) {}

  func recordEvent(_ name: StaticString, attributes: SpanAttributes) {}
}
