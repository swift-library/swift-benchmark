// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

public enum ReportFormat: String, Sendable, Codable, CaseIterable {
  case console
  case json
  case markdown
  case speedscope

  public func render(_ document: ReportDocument) throws -> String {
    switch self {
    case .console:
      return ConsoleReportRenderer.render(document)
    case .json:
      return try JSONReportRenderer.render(document)
    case .markdown:
      return MarkdownReportRenderer.render(document)
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
    baselineMetric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy = .relativePercentage(10),
    budgets: [BudgetPolicy] = [],
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
      baselineMetric: baselineMetric,
      threshold: threshold,
      budgets: budgets,
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
    baselineMetric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy = .relativePercentage(10),
    budgets: [BudgetPolicy] = [],
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
        baselineMetric: baselineMetric,
        threshold: threshold,
        budgets: budgets,
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
    baselineMetric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy = .relativePercentage(10),
    budgets: [BudgetPolicy] = [],
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

    for result in results {
      let scope = ReportScope(
        runID: metadata.id,
        suiteID: ReportIDFactory.suite(result.suiteName),
        caseID: ReportIDFactory.benchmarkCase(
          suiteName: result.suiteName,
          caseName: result.caseName
        )
      )
      for provider in metricProviders {
        let metrics = await provider.metrics(for: scope)
        try BenchmarkCommand.validate(metrics: metrics, requirement: provider.requirement)
        collectedDiagnostics.append(contentsOf: metrics)
      }
      for exporter in traceExporters {
        let exported = await exporter.attachments(for: scope)
        if exporter.requirement == .required, exported.isEmpty {
          throw BenchmarkCommandError.requiredAttachmentUnavailable(scope: scope)
        }
        collectedAttachments.append(contentsOf: exported)
      }
    }

    let document = await reportRecorder.document(
      metadata: metadata,
      baseline: baseline,
      baselineMetric: baselineMetric,
      threshold: threshold,
      budgets: budgets,
      attributions: collectedAttributions,
      diagnostics: collectedDiagnostics,
      attachments: collectedAttachments
    )
    for observer in observers {
      await observer.runDidFinish(scope: runScope)
    }
    return document
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
