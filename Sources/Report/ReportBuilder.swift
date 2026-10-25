// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

public actor ReportRecorder: BenchmarkEventRecorder {
  private var records: [Benchmark.Event.Stream.Record] = []
  private var nextSequence = 0

  public init() {}

  public func record(_ record: Benchmark.Event.Stream.Record) {
    records.append(
      Benchmark.Event.Stream.Record(
        sequence: nextSequence,
        kind: record.kind,
        context: record.context
      )
    )
    nextSequence += 1
  }

  public func snapshot() -> [Benchmark.Event.Stream.Record] {
    records
  }

  public func document(
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = []
  ) -> ReportDocument {
    ReportBuilder(records: records).document(
      metadata: metadata,
      baseline: baseline,
      comparison: comparison,
      attributions: attributions,
      diagnostics: diagnostics,
      attachments: attachments
    )
  }
}

public struct ReportBuilder: Sendable {
  public var records: [Benchmark.Event.Stream.Record]

  public init(records: [Benchmark.Event.Stream.Record]) {
    self.records = records.sorted { $0.sequence < $1.sequence }
  }

  public func document(
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = []
  ) -> ReportDocument {
    let cases = caseAccumulators()
    let suites = Dictionary(grouping: cases.values, by: \.suiteName)
      .keys
      .sorted()
      .map { suiteName -> SuiteReport in
        let suiteID = ReportIDFactory.suite(suiteName)
        let reports = (Dictionary(grouping: cases.values, by: \.suiteName)[suiteName] ?? [])
          .sorted { $0.caseName < $1.caseName }
          .map { accumulator -> CaseReport in
            let caseID = ReportIDFactory.benchmarkCase(
              suiteName: accumulator.suiteName,
              caseName: accumulator.caseName
            )
            let scope = ReportScope(runID: metadata.id, suiteID: suiteID, caseID: caseID)
            let sourceLocation = accumulator.sourceLocation.map(SourceLocationReport.init)
            let measurement = Report.Measurement(
              rows: accumulator.rows
                .sorted { lhs, rhs in
                  switch (lhs.key.scale, rhs.key.scale) {
                  case (nil, nil):
                    return (lhs.key.id ?? "") < (rhs.key.id ?? "")
                  case (nil, _):
                    return true
                  case (_, nil):
                    return false
                  case (let lhs?, let rhs?):
                    return lhs < rhs
                  }
                }
                .map { row, samples in
                  Report.Measurement.Row(
                    id: row.id,
                    size: row.scale,
                    arguments: row.arguments,
                    samples: samples.sorted { $0.iteration < $1.iteration },
                    metrics: accumulator.metrics
                  )
                }
            )
            let compared = comparison.compare(
              suiteName: accumulator.suiteName,
              caseName: accumulator.caseName,
              scope: scope,
              measurement: measurement,
              baseline: baseline
            )
            return CaseReport(
              id: caseID,
              scope: scope,
              name: accumulator.caseName,
              sourceLocation: sourceLocation,
              configuration: BenchmarkConfigurationReport(
                warmup: accumulator.configurationWarmup ?? "unknown",
                iterations: accumulator.configurationIterations ?? "unknown",
                batching: accumulator.configurationBatching ?? "unknown"
              ),
              tags: accumulator.tags,
              measurement: measurement,
              baselines: compared.baselines,
              budgets: compared.budgets,
              dimensionCurves: Report.DimensionCurve.curves(
                suiteName: accumulator.suiteName,
                caseName: accumulator.caseName,
                scope: scope,
                measurement: measurement,
                sourceLocation: sourceLocation
              ),
              attributions: attributions.filter { $0.scope.caseID == caseID },
              diagnostics: diagnostics.filter { $0.scope.caseID == caseID },
              attachments: attachments.filter { $0.scope.caseID == caseID },
              warnings: compared.warnings
            )
          }
        return SuiteReport(
          id: suiteID,
          scope: ReportScope(runID: metadata.id, suiteID: suiteID),
          name: suiteName,
          cases: reports
        )
      }

    return ReportDocument(
      metadata: metadata,
      suites: suites,
      warnings: ReportWarning.runWarnings(metadata: metadata, baseline: baseline)
    )
  }

  private func caseAccumulators() -> [CaseKey: CaseAccumulator] {
    var cases: [CaseKey: CaseAccumulator] = [:]
    for record in records {
      guard let suiteName = record.context.suiteName,
        let caseName = record.context.caseName
      else {
        continue
      }
      let key = CaseKey(suiteName: suiteName, caseName: caseName)
      cases[key, default: CaseAccumulator(suiteName: suiteName, caseName: caseName)]
        .merge(context: record.context)

      guard record.kind == .sampleRecorded,
        let iteration = record.context.iteration
      else {
        continue
      }
      let knownMetrics = cases[key]?.metrics ?? []
      cases[key]?.metrics = Report.mergedMetrics([knownMetrics, record.context.metrics])
      let sample = SampleReport(
        id: ReportIDFactory.sample(
          suiteName: suiteName,
          caseName: caseName,
          size: record.context.size,
          rowID: record.context.argumentRowID,
          iteration: iteration
        ),
        iterationID: ReportIDFactory.iteration(
          suiteName: suiteName,
          caseName: caseName,
          size: record.context.size,
          rowID: record.context.argumentRowID,
          iteration: iteration
        ),
        iteration: iteration,
        batchSize: record.context.batchSize ?? 1,
        values: record.context.values
      )
      let row = Benchmark.ArgumentRow(
        id: record.context.argumentRowID,
        arguments: record.context.arguments,
        scale: record.context.size
      )
      cases[key]?.rows[row, default: []].append(sample)
    }
    return cases.filter { !$0.value.rows.isEmpty }
  }
}

private struct CaseKey: Hashable {
  var suiteName: String
  var caseName: String
}

private struct CaseAccumulator {
  var suiteName: String
  var caseName: String
  var tags: [String] = []
  var sourceLocation: BenchmarkSourceLocation?
  var configurationWarmup: String?
  var configurationIterations: String?
  var configurationBatching: String?
  var metrics: [Benchmark.Metric] = []
  var rows: [Benchmark.ArgumentRow: [SampleReport]] = [:]

  mutating func merge(context: Benchmark.Event.Context) {
    if tags.isEmpty, !context.tags.isEmpty {
      tags = context.tags
    }
    if sourceLocation == nil {
      sourceLocation = context.sourceLocation
    }
    if configurationWarmup == nil {
      configurationWarmup = context.configurationWarmup
    }
    if configurationIterations == nil {
      configurationIterations = context.configurationIterations
    }
    if configurationBatching == nil {
      configurationBatching = context.configurationBatching
    }
  }
}
