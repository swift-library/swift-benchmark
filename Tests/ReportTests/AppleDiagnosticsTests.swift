// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Report
import Testing

@Suite("Apple Diagnostics")
struct AppleDiagnosticsTests {
  @Test
  func traceArtifactExporterAttachesTheTraceOnlyWhenItExists() async {
    let scope = ReportScope(
      runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
    let artifact = TraceArtifact(
      tracePath: "/tmp/run.trace",
      command: ["xcrun", "xctrace", "record"],
      metadata: ["tool": "xctrace"]
    )

    let present = await TraceArtifactExporter(artifact: artifact, fileExists: { _ in true })
      .attachments(for: scope)
    let missing = await TraceArtifactExporter(artifact: artifact, fileExists: { _ in false })
      .attachments(for: scope)

    #expect(present.map(\.kind) == [.trace])
    #expect(present.first?.contentType == "application/vnd.apple.instruments.trace")
    #expect(present.first?.metadata == ["tool": "xctrace", "command": "xcrun xctrace record"])
    #expect(missing.isEmpty)
  }

  @Test
  func requiredMissingTraceArtifactIsValidatedByBenchmarkCommand() async throws {
    let scope = ReportScope(
      runID: "run:apple", suiteID: "suite:parser", caseID: "case:parser.parse")
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
      #expect(
        arguments.prefix(6) == [
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

  @Test(.timeLimit(.minutes(1)))
  func xctraceRecorderDrainsOutputWhileTheCommandRuns() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-xcrun-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let xcrun = directory.appendingPathComponent("xcrun")
    // Each stream carries more than a pipe buffers.
    try """
    #!/bin/sh
    head -c 1048576 /dev/zero | tr '\\0' o
    head -c 1048576 /dev/zero | tr '\\0' e >&2
    """.write(to: xcrun, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcrun.path)
    let tracePath = directory.appendingPathComponent("run.trace").path

    let artifact = try await XctraceRecorder(xcrunPath: xcrun.path)
      .record(executablePath: "/bin/true", outputTracePath: tracePath)

    #expect(artifact.tracePath == tracePath)
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
