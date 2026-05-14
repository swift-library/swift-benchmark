import Foundation

import Benchmark
import Instruments
import Report
import Testing

@BenchmarkSuite("Host", .tag("macro-host"))
struct HostBenchmarks {
  @Benchmark("Measured", .tag("fast"))
  func measured() {
    blackHole(1)
  }
}

@Suite("Benchmark Command", .serialized)
struct BenchmarkCommandTests {
  @Test
  func commandRunsSuitesThroughBenchmarkAndReport() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(2))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let output = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
      suites: [suite],
      metadata: .fixture(),
      format: .json
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.name == "Measured")
    #expect(report.samples.map(\.durationNanoseconds) == [100, 100])
    #expect(document.summary.caseCount == 1)
  }

  @Test
  func commandCollectsOptionalDiagnosticsIntoReport() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let output = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
      suites: [suite],
      metadata: .fixture(),
      metricProviders: [
        UnavailableMetricProvider(metricName: "metrickit.cpu", reason: "MetricKit unavailable")
      ],
      format: .json
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.diagnostics.map(\.name) == ["metrickit.cpu"])
    #expect(report.diagnostics.first?.state.kind == .unavailable)
    #expect(document.summary.unavailableDiagnosticCount == 1)
  }

  @Test
  func commandCanCaptureBenchmarkIterationTimelineAttribution() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(2))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }
    let output = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
      suites: [suite],
      metadata: .fixture(),
      timelineCapture: .benchmarkIterations,
      format: .json
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.attributions.count == 2)
    #expect(report.attributions.map { $0.scope.sampleID?.rawValue } == [
      "sample:command.measured.0",
      "sample:command.measured.1",
    ])
    #expect(report.attributions.allSatisfy { attribution in
      attribution.spans.map(\.name) == ["BenchmarkIteration"]
        && attribution.events.map(\.name) == ["BenchmarkIterationMeasured"]
        && attribution.spanSummaries.map(\.name) == ["BenchmarkIteration"]
    })
  }

  @Test
  func commandCapturesWorkloadSpansAsTimelineDescendants() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
    ) {
      Benchmark("Measured") {
        Instruments.current.span("Parser.normalize") {
          Instruments.current.event("Parser.cacheHit")
          blackHole(1)
        }
      }
    }
    let output = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
      suites: [suite],
      metadata: .fixture(),
      timelineCapture: .benchmarkIterations,
      format: .json
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
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
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
    ) {
      Benchmark("Throws") {
        throw DummyError.boom
      }
    }

    await Instruments.withCurrentRecorder(previous) {
      do {
        _ = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
          suites: [suite],
          metadata: .fixture(),
          timelineCapture: .benchmarkIterations,
          format: .json
        )
        Issue.record("Expected throwing benchmark to fail")
      } catch {
        #expect((Instruments.current as? IdentityRecorder) === previous)
      }
    }
  }

  @Test
  func commandFailsWhenRequiredDiagnosticIsUnavailable() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }

    do {
      _ = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
        suites: [suite],
        metadata: .fixture(),
        metricProviders: [
          UnavailableMetricProvider(
            metricName: "metrickit.cpu",
            reason: "MetricKit unavailable",
            requirement: .required
          )
        ],
        format: .json
      )
      Issue.record("Expected required unavailable diagnostic to fail")
    } catch let error as BenchmarkCommandError {
      #expect(error.description.contains("metrickit.cpu"))
    }
  }

  @Test
  func commandFailsWhenRequiredTraceArtifactIsUnavailable() async throws {
    let suite = BenchmarkSuite(
      "Command",
      configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(1))
    ) {
      Benchmark("Measured") {
        blackHole(1)
      }
    }

    do {
      _ = try await BenchmarkCommand(runner: BenchmarkRunner(clock: StepClock(step: 100))).run(
        suites: [suite],
        metadata: .fixture(),
        traceExporters: [
          TraceArtifactExporter(
            artifact: TraceArtifact(tracePath: "/tmp/missing.trace"),
            requirement: .required,
            fileExists: { _ in false }
          )
        ],
        format: .json
      )
      Issue.record("Expected required missing trace artifact to fail")
    } catch let error as BenchmarkCommandError {
      #expect(error.description.contains("Required diagnostic attachment"))
    }
  }

  @Test
  func benchmarkHostListsAndRunsDiscoveredMacrosThroughPlan() async throws {
    let list = try await BenchmarkHost.render(
      discoveries: [HostBenchmarks.self],
      arguments: ["list", "--format", "json"],
      metadata: .fixture()
    )
    let entries = try JSONDecoder().decode([BenchmarkListEntry].self, from: Data(list.utf8))
    let filteredList = try await BenchmarkHost.render(
      discoveries: [HostBenchmarks.self],
      arguments: ["list", "--tag", "fast", "--format", "json"],
      metadata: .fixture()
    )
    let filteredEntries = try JSONDecoder().decode(
      [BenchmarkListEntry].self,
      from: Data(filteredList.utf8)
    )
    let output = try await BenchmarkHost.render(
      discoveries: [HostBenchmarks.self],
      arguments: ["run", "--tag", "macro-host", "--format", "json"],
      metadata: .fixture()
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))

    #expect(entries.map(\.suite) == ["Host"])
    #expect(entries.map(\.caseName) == ["Measured"])
    #expect(entries.map(\.tags) == [["macro-host", "fast"]])
    #expect(filteredEntries.map(\.caseName) == ["Measured"])
    #expect(document.suites.first?.cases.first?.name == "Measured")
    #expect(document.suites.first?.cases.first?.tags == ["macro-host", "fast"])
    #expect(document.suites.first?.cases.first?.measurement.rows.count == 1)
  }

  @Test
  func benchmarkHostAppliesWarmupIterationAndTagOverrides() async throws {
    let output = try await BenchmarkHost.render(
      discoveries: [HostBenchmarks.self],
      arguments: [
        "run",
        "--tag",
        "fast",
        "--warmup",
        "0",
        "--iterations",
        "2",
        "--format",
        "json",
      ],
      metadata: .fixture()
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
    let report = try #require(document.suites.first?.cases.first)

    #expect(report.tags == ["macro-host", "fast"])
    #expect(report.samples.count == 2)
    #expect(report.configuration.warmup == "none")
    #expect(report.configuration.iterations == "iterations(2)")
  }

  @Test
  func benchmarkHostAttachesTraceArtifactsAndDiagnosticsFromCLIOptions() async throws {
    let tracePath = FileManager.default.temporaryDirectory
      .appendingPathComponent("benchmark-host-\(UUID().uuidString).trace")
      .path
    try FileManager.default.createDirectory(atPath: tracePath, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(atPath: tracePath)
    }

    let output = try await BenchmarkHost.render(
      discoveries: [HostBenchmarks.self],
      arguments: [
        "run",
        "--tag",
        "fast",
        "--format",
        "json",
        "--trace",
        tracePath,
        "--trace-tool",
        "xctrace",
        "--trace-template",
        "Time Profiler",
        "--trace-command",
        "xcrun xctrace record",
        "--optional-diagnostic",
        "diagnostic.example",
      ],
      metadata: .fixture()
    )
    let document = try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
    let report = try #require(document.suites.first?.cases.first)
    let attachment = try #require(report.attachments.first)

    #expect(report.diagnostics.map(\.name) == ["diagnostic.example"])
    #expect(attachment.kind == .trace)
    #expect(attachment.location == tracePath)
    #expect(attachment.metadata["tool"] == "xctrace")
    #expect(attachment.metadata["template"] == "Time Profiler")
    #expect(attachment.metadata["command"] == "xcrun xctrace record")
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

private final class IdentityRecorder: Recorder, @unchecked Sendable {
  func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken {
    .empty
  }

  func endSpan(_ token: SpanToken) {}

  func recordEvent(_ name: StaticString, attributes: SpanAttributes) {}
}
