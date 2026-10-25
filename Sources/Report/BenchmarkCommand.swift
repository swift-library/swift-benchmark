// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

public enum ReportFormat: String, Sendable, Codable, CaseIterable {
  case console
  case json
  case speedscope

  public func render(_ document: ReportDocument) throws -> String {
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

public enum TimelineCapturePolicy: String, Sendable, Codable, CaseIterable {
  case disabled
  case benchmarkIterations
}

public struct BenchmarkCommand: Sendable {
  public var runner: BenchmarkRunner

  public init(runner: BenchmarkRunner = BenchmarkRunner()) {
    self.runner = runner
  }

  public func run(
    suites: [BenchmarkSuite],
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = [],
    timelineCapture: TimelineCapturePolicy = .disabled,
    executionObservers: [any BenchmarkExecutionObserver] = [],
    observers: [any BenchmarkObserver] = [],
    metricProviders: [any MetricProvider] = [],
    traceExporters: [any TraceExporter] = [],
    format: ReportFormat = .console
  ) async throws -> String {
    try await run(
      plan: BenchmarkRunner.Plan(suites: suites),
      metadata: metadata,
      baseline: baseline,
      comparison: comparison,
      attributions: attributions,
      diagnostics: diagnostics,
      attachments: attachments,
      timelineCapture: timelineCapture,
      executionObservers: executionObservers,
      observers: observers,
      metricProviders: metricProviders,
      traceExporters: traceExporters,
      format: format
    )
  }

  public func run(
    plan: BenchmarkRunner.Plan,
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = [],
    timelineCapture: TimelineCapturePolicy = .disabled,
    executionObservers: [any BenchmarkExecutionObserver] = [],
    observers: [any BenchmarkObserver] = [],
    metricProviders: [any MetricProvider] = [],
    traceExporters: [any TraceExporter] = [],
    format: ReportFormat = .console
  ) async throws -> String {
    try format.render(
      await report(
        plan: plan,
        metadata: metadata,
        baseline: baseline,
        comparison: comparison,
        attributions: attributions,
        diagnostics: diagnostics,
        attachments: attachments,
        timelineCapture: timelineCapture,
        executionObservers: executionObservers,
        observers: observers,
        metricProviders: metricProviders,
        traceExporters: traceExporters
      )
    )
  }

  func report(
    plan: BenchmarkRunner.Plan,
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = [],
    timelineCapture: TimelineCapturePolicy = .disabled,
    executionObservers: [any BenchmarkExecutionObserver] = [],
    observers: [any BenchmarkObserver] = [],
    metricProviders: [any MetricProvider] = [],
    traceExporters: [any TraceExporter] = []
  ) async throws -> ReportDocument {
    let runScope = ReportScope(runID: metadata.id)
    for observer in observers {
      await observer.runDidStart(scope: runScope)
    }
    let timelineObserver: BenchmarkTimelineObserver?
    switch timelineCapture {
    case .disabled:
      timelineObserver = nil
    case .benchmarkIterations:
      timelineObserver = BenchmarkTimelineObserver()
    }
    var benchmarkObservers = executionObservers
    if let timelineObserver {
      benchmarkObservers.append(timelineObserver)
    }
    let reportRecorder = ReportRecorder()
    let results = try await runner.run(
      plan,
      observers: benchmarkObservers,
      eventRecorders: [reportRecorder]
    )
    var collectedDiagnostics = diagnostics
    var collectedAttachments = attachments
    var collectedAttributions = attributions
    if let timelineObserver {
      collectedAttributions.append(
        contentsOf: TimelineCorrelator.attributions(
          from: timelineObserver.recorder.snapshot(),
          runID: metadata.id,
          results: results
        )
      )
    }

    let collected = try await Self.collect(
      scopes: results.map { caseScope(runID: metadata.id, $0.suiteName, $0.caseName) },
      metricProviders: metricProviders,
      traceExporters: traceExporters
    )
    collectedDiagnostics += collected.diagnostics
    collectedAttachments += collected.attachments

    let document = await reportRecorder.document(
      metadata: metadata,
      baseline: baseline,
      comparison: comparison,
      attributions: collectedAttributions,
      diagnostics: collectedDiagnostics,
      attachments: collectedAttachments
    )
    for observer in observers {
      await observer.runDidFinish(scope: runScope)
    }
    return document
  }

  /// Builds the report for measurements recorded by separate host processes,
  /// in the order they ran; run metadata comes from the first.
  package static func document(
    measurements: [HostMeasurement],
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    metricProviders: [any MetricProvider] = [],
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
    let collected = try await collect(
      scopes: scopes, metricProviders: metricProviders, traceExporters: traceExporters)
    return ReportBuilder(records: records).document(
      metadata: metadata,
      baseline: baseline,
      comparison: comparison,
      attributions: measurements.flatMap(\.attributions),
      diagnostics: collected.diagnostics,
      attachments: collected.attachments
    )
  }

  /// Asks every provider and exporter about each case, failing when a
  /// required one has nothing.
  private static func collect(
    scopes: [ReportScope],
    metricProviders: [any MetricProvider],
    traceExporters: [any TraceExporter]
  ) async throws -> (diagnostics: [DiagnosticMetric], attachments: [DiagnosticAttachment]) {
    var diagnostics: [DiagnosticMetric] = []
    var attachments: [DiagnosticAttachment] = []
    for scope in scopes {
      for provider in metricProviders {
        let metrics = await provider.metrics(for: scope)
        try validate(metrics: metrics, requirement: provider.requirement)
        diagnostics.append(contentsOf: metrics)
      }
      for exporter in traceExporters {
        let exported = await exporter.attachments(for: scope)
        if exporter.requirement == .required, exported.isEmpty {
          throw BenchmarkCommandError.requiredAttachmentUnavailable(scope: scope)
        }
        attachments.append(contentsOf: exported)
      }
    }
    return (diagnostics, attachments)
  }

  private static func validate(
    metrics: [DiagnosticMetric],
    requirement: DiagnosticRequirement
  ) throws {
    guard requirement == .required else {
      return
    }
    for metric in metrics where metric.state.kind != .measured {
      throw BenchmarkCommandError.requiredDiagnosticUnavailable(metric: metric)
    }
  }
}

public enum BenchmarkCommandError: Error, CustomStringConvertible {
  case requiredDiagnosticUnavailable(metric: DiagnosticMetric)
  case requiredAttachmentUnavailable(scope: ReportScope)

  public var description: String {
    switch self {
    case .requiredDiagnosticUnavailable(let metric):
      return "Required diagnostic '\(metric.name)' is \(metric.state.kind.rawValue)."
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
