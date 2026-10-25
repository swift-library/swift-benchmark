// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

/// The forms a report can be written in.
package enum ReportFormat: String, Sendable, Codable, CaseIterable {
  case console
  case json
  case speedscope

  package func render(_ document: ReportDocument) throws -> String {
    switch self {
    case .console:
      return ConsoleReportRenderer.render(document)
    case .json:
      return try JSONReportRenderer.render(document)
    case .speedscope:
      return try SpeedscopeReportRenderer.render(document)
    }
  }
}

/// Whether a run records the Instruments timeline of each measured call.
package enum TimelineCapturePolicy: String, Sendable, Codable, CaseIterable {
  case disabled
  case benchmarkIterations
}

/// Measures benchmarks and builds their report: in this process for the
/// testing adapters, or from the measurements host processes recorded for
/// the CLI.
package struct BenchmarkCommand: Sendable {
  package var runner: BenchmarkRunner

  package init(runner: BenchmarkRunner = BenchmarkRunner()) {
    self.runner = runner
  }

  /// Measures `plan` in this process and reports it.
  package func report(
    plan: BenchmarkRunner.Plan,
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    timelineCapture: TimelineCapturePolicy = .disabled,
    traceExporters: [any TraceExporter] = []
  ) async throws -> ReportDocument {
    let timelineObserver: BenchmarkTimelineObserver?
    switch timelineCapture {
    case .disabled:
      timelineObserver = nil
    case .benchmarkIterations:
      timelineObserver = BenchmarkTimelineObserver()
    }
    let recorder = ReportRecorder()
    let results = try await runner.run(
      plan,
      observers: timelineObserver.map { [$0] } ?? [],
      eventRecorders: [recorder]
    )
    let attributions =
      timelineObserver.map {
        TimelineCorrelator.attributions(
          from: $0.recorder.snapshot(), runID: metadata.id, results: results)
      } ?? []
    let attachments = try await Self.attachments(
      scopes: results.map { caseScope(runID: metadata.id, $0.suiteName, $0.caseName) },
      exporters: traceExporters
    )
    return await recorder.document(
      metadata: metadata,
      baseline: baseline,
      comparison: comparison,
      attributions: attributions,
      attachments: attachments
    )
  }

  /// Builds the report for measurements recorded by separate host processes,
  /// in the order they ran; run metadata comes from the first.
  package static func document(
    measurements: [HostMeasurement],
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    traceExporters: [any TraceExporter] = []
  ) async throws -> ReportDocument? {
    guard let metadata = measurements.first?.metadata else {
      return nil
    }
    let records = measurements.flatMap(\.records).enumerated().map { index, record in
      Benchmark.Event.Stream.Record(sequence: index, kind: record.kind, context: record.context)
    }
    var scopes: [ReportScope] = []
    for record in records {
      guard let suiteName = record.context.suiteName, let caseName = record.context.caseName
      else {
        continue
      }
      let scope = caseScope(runID: metadata.id, suiteName, caseName)
      if !scopes.contains(scope) {
        scopes.append(scope)
      }
    }
    return ReportBuilder(records: records).document(
      metadata: metadata,
      baseline: baseline,
      comparison: comparison,
      attributions: measurements.flatMap(\.attributions),
      attachments: try await attachments(scopes: scopes, exporters: traceExporters)
    )
  }

  /// Asks every exporter for each case's attachments, failing when a
  /// required exporter has none.
  private static func attachments(
    scopes: [ReportScope],
    exporters: [any TraceExporter]
  ) async throws -> [DiagnosticAttachment] {
    var attachments: [DiagnosticAttachment] = []
    for scope in scopes {
      for exporter in exporters {
        let exported = await exporter.attachments(for: scope)
        if exporter.requirement == .required, exported.isEmpty {
          throw BenchmarkCommandError.requiredAttachmentUnavailable(scope: scope)
        }
        attachments.append(contentsOf: exported)
      }
    }
    return attachments
  }
}

package enum BenchmarkCommandError: Error, CustomStringConvertible {
  case requiredAttachmentUnavailable(scope: ReportScope)

  package var description: String {
    switch self {
    case .requiredAttachmentUnavailable(let scope):
      return "Required diagnostic attachment is unavailable for scope \(scope)."
    }
  }
}

private func caseScope(runID: ReportID, _ suiteName: String, _ caseName: String) -> ReportScope {
  ReportScope(
    runID: runID,
    suiteID: ReportIDFactory.suite(suiteName),
    caseID: ReportIDFactory.benchmarkCase(suiteName: suiteName, caseName: caseName)
  )
}
