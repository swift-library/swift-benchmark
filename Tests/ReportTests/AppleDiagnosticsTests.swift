import Report
import Testing

@Suite("Apple Diagnostics")
struct AppleDiagnosticsTests {
  @Test
  func metricKitProviderReportsUnavailableWithoutPlatformPayload() async {
    let scope = ReportScope(runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
    let metrics = await MetricKitDiagnosticProvider().metrics(for: scope)

    #expect(metrics.map(\.name) == [AppleDiagnosticMetricName.metricKitPayload])
    #expect(metrics.first?.state.kind == .unavailable)
    #expect(metrics.first?.state.value == nil)
  }

  @Test
  func metricKitProviderMapsSnapshotToRunScopedMetrics() async {
    let scope = ReportScope(runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
    let provider = MetricKitDiagnosticProvider(
      source: StaticMetricKitSnapshotSource(
        snapshot: MetricKitDiagnosticSnapshot(
          cpuTimeSeconds: 1.5,
          peakMemoryBytes: 4096,
          logicalWritesBytes: 2048,
          hangCount: 1,
          diagnosticCount: 2
        )
      )
    )

    let metrics = await provider.metrics(for: scope)

    #expect(metrics.map(\.name) == [
      AppleDiagnosticMetricName.metricKitCPUTimeSeconds,
      AppleDiagnosticMetricName.metricKitPeakMemoryBytes,
      AppleDiagnosticMetricName.metricKitLogicalWritesBytes,
      AppleDiagnosticMetricName.metricKitHangCount,
      AppleDiagnosticMetricName.metricKitDiagnosticCount,
    ])
    #expect(metrics.map(\.state.kind).allSatisfy { $0 == .measured })
    #expect(metrics.map(\.state.value) == [1.5, 4096, 2048, 1, 2])
  }

  @Test
  func metricKitAttachmentExporterReturnsStructuredPayloadAttachments() async {
    let scope = ReportScope(runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
    let attachment = DiagnosticAttachment(
      id: "attachment:metrickit-payload",
      scope: scope,
      kind: .structuredData,
      title: "MetricKit payload",
      location: "/tmp/metrickit.json",
      contentType: "application/json",
      metadata: ["scope": "run-session"]
    )
    let exporter = MetricKitAttachmentExporter(
      source: StaticMetricKitSnapshotSource(
        snapshot: MetricKitDiagnosticSnapshot(attachments: [attachment])
      )
    )

    let attachments = await exporter.attachments(for: scope)

    #expect(attachments == [attachment])
  }

  @Test
  func traceArtifactExporterAttachesTraceAndOfficialExportsOnlyWhenPresent() async {
    let scope = ReportScope(runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
    let exporter = TraceArtifactExporter(
      artifact: TraceArtifact(
        tracePath: "/tmp/run.trace",
        exportedXMLPath: "/tmp/run.xml",
        tableOfContentsPath: "/tmp/run-toc.xml",
        command: ["xctrace", "export", "--input", "/tmp/run.trace"],
        metadata: ["tool": "xctrace"]
      ),
      fileExists: { path in
        path == "/tmp/run.trace" || path == "/tmp/run.xml" || path == "/tmp/run-toc.xml"
      }
    )

    let attachments = await exporter.attachments(for: scope)

    #expect(attachments.map(\.kind) == [.trace, .structuredData, .structuredData])
    #expect(attachments.map(\.contentType) == [
      "application/vnd.apple.instruments.trace",
      "application/xml",
      "application/xml",
    ])
    #expect(attachments.allSatisfy { $0.metadata["command"]?.contains("xctrace export") == true })
  }

  @Test
  func requiredMissingTraceArtifactIsValidatedByBenchmarkCommand() async throws {
    let scope = ReportScope(runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
    let exporter = TraceArtifactExporter(
      artifact: TraceArtifact(tracePath: "/tmp/missing.trace"),
      requirement: .required,
      fileExists: { _ in false }
    )

    let attachments = await exporter.attachments(for: scope)

    #expect(attachments.isEmpty)
  }

  @Test
  func xctraceRecorderBuildsRecordCommandAndTraceArtifactProvenance() async throws {
    let recorder = XctraceRecorder(xcrunPath: "/usr/bin/xcrun") { arguments in
      #expect(arguments.prefix(6) == [
        "xctrace",
        "record",
        "--template",
        "Time Profiler",
        "--output",
        "/tmp/run.trace",
      ])
      #expect(arguments.contains("--launch"))
      #expect(arguments.suffix(2) == ["--format", "json"])
      return XctraceCommandResult(terminationStatus: 0)
    }

    let artifact = try await recorder.record(
      executablePath: "/tmp/generated-host",
      executableArguments: ["--format", "json"],
      outputTracePath: "/tmp/run.trace",
      metadata: ["run": "fixture"]
    )

    #expect(artifact.tracePath == "/tmp/run.trace")
    #expect(artifact.command.joined(separator: " ").contains("xctrace record"))
    #expect(artifact.metadata["tool"] == "xctrace")
    #expect(artifact.metadata["template"] == "Time Profiler")
    #expect(artifact.metadata["run"] == "fixture")
  }

  @Test
  func xctraceRecorderSurfacesUnavailableCommandFailure() async {
    let recorder = XctraceRecorder(xcrunPath: "/missing/xcrun") { _ in
      XctraceCommandResult(terminationStatus: 127, standardError: "xcrun unavailable")
    }

    do {
      _ = try await recorder.record(
        executablePath: "/tmp/generated-host",
        outputTracePath: "/tmp/run.trace"
      )
      Issue.record("Expected xctrace failure")
    } catch let error as XctraceRecorderError {
      #expect(error.description.contains("xcrun unavailable"))
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }
}
