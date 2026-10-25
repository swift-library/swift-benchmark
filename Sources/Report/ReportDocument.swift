// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

public enum ReportExecutionStatus: String, Sendable, Codable {
  case passed
  case failed
  case unavailable
}

public struct ReportVerdictCause: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    case executionFailed
    case baselineRegression
    case budgetExceeded
    case diagnosticFailed
  }

  public var kind: Kind
  public var scope: ReportScope
  public var message: String
  public var metric: Benchmark.Metric?
  public var statistic: Report.Statistic?
  /// The measured value, in the metric's unit.
  public var actual: Double?
  /// The baseline value or budget limit, in the metric's unit.
  public var expected: Double?
  public var delta: Double?
  public var percentageDelta: Double?
  public var diagnosticID: ReportID?
  public var budget: BudgetPolicy?

  public init(
    kind: Kind,
    scope: ReportScope,
    message: String,
    metric: Benchmark.Metric? = nil,
    statistic: Report.Statistic? = nil,
    actual: Double? = nil,
    expected: Double? = nil,
    delta: Double? = nil,
    percentageDelta: Double? = nil,
    diagnosticID: ReportID? = nil,
    budget: BudgetPolicy? = nil
  ) {
    self.kind = kind
    self.scope = scope
    self.message = message
    self.metric = metric
    self.statistic = statistic
    self.actual = actual
    self.expected = expected
    self.delta = delta
    self.percentageDelta = percentageDelta
    self.diagnosticID = diagnosticID
    self.budget = budget
  }
}

public struct CaseReport: Sendable, Equatable, Codable {
  public var id: ReportID
  public var scope: ReportScope
  public var name: String
  public var sourceLocation: SourceLocationReport?
  public var configuration: BenchmarkConfigurationReport
  public var tags: [String]
  public var measurement: Report.Measurement
  /// One comparison per metric that both this case and its baseline measured.
  public var baselines: [BaselineComparison]
  public var budgets: [BudgetComparison]
  public var dimensionCurves: [Report.DimensionCurve]
  public var attribution: TimelineAttribution?
  public var attributions: [TimelineAttribution]
  public var diagnostics: [DiagnosticMetric]
  public var attachments: [DiagnosticAttachment]
  public var status: ReportExecutionStatus
  public var verdict: ReportVerdict
  public var verdictCauses: [ReportVerdictCause]
  /// Conditions that make this case's comparisons less trustworthy.
  public var warnings: [ReportWarning]

  public var samples: [SampleReport] {
    measurement.samples
  }

  public init(
    id: ReportID,
    scope: ReportScope,
    name: String,
    sourceLocation: SourceLocationReport? = nil,
    configuration: BenchmarkConfigurationReport,
    tags: [String] = [],
    measurement: Report.Measurement,
    baselines: [BaselineComparison] = [],
    budgets: [BudgetComparison] = [],
    dimensionCurves: [Report.DimensionCurve] = [],
    attribution: TimelineAttribution? = nil,
    attributions: [TimelineAttribution]? = nil,
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = [],
    status: ReportExecutionStatus = .passed,
    verdictCauses: [ReportVerdictCause]? = nil,
    warnings: [ReportWarning] = []
  ) {
    self.id = id
    self.scope = scope
    self.name = name
    self.sourceLocation = sourceLocation
    self.configuration = configuration
    self.tags = tags
    self.measurement = measurement
    self.baselines = baselines
    self.budgets = budgets
    self.dimensionCurves = dimensionCurves
    self.attributions = attributions ?? attribution.map { [$0] } ?? []
    self.attribution = attribution ?? self.attributions.first
    self.diagnostics = diagnostics
    self.attachments = attachments
    self.status = status
    self.warnings = warnings
    self.verdictCauses =
      verdictCauses
      ?? CaseReport.makeVerdictCauses(
        scope: scope,
        status: status,
        baselines: baselines,
        budgets: budgets,
        diagnostics: diagnostics
      )
    if !self.verdictCauses.isEmpty {
      self.verdict = .failed
    } else if !baselines.isEmpty || budgets.contains(where: { $0.verdict != .notCompared }) {
      self.verdict = .passed
    } else {
      self.verdict = .notCompared
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case scope
    case name
    case sourceLocation
    case configuration
    case tags
    case measurement
    case baselines
    case budgets
    case dimensionCurves
    case attribution
    case attributions
    case diagnostics
    case attachments
    case status
    case verdict
    case verdictCauses
    case warnings
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(ReportID.self, forKey: .id),
      scope: try container.decode(ReportScope.self, forKey: .scope),
      name: try container.decode(String.self, forKey: .name),
      sourceLocation: try container.decodeIfPresent(
        SourceLocationReport.self, forKey: .sourceLocation),
      configuration: try container.decode(
        BenchmarkConfigurationReport.self, forKey: .configuration),
      tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
      measurement: try container.decode(Report.Measurement.self, forKey: .measurement),
      baselines: try container.decodeIfPresent([BaselineComparison].self, forKey: .baselines)
        ?? [],
      budgets: try container.decodeIfPresent([BudgetComparison].self, forKey: .budgets) ?? [],
      dimensionCurves: try container.decodeIfPresent(
        [Report.DimensionCurve].self, forKey: .dimensionCurves) ?? [],
      attribution: try container.decodeIfPresent(TimelineAttribution.self, forKey: .attribution),
      attributions: try container.decodeIfPresent(
        [TimelineAttribution].self, forKey: .attributions),
      diagnostics: try container.decodeIfPresent([DiagnosticMetric].self, forKey: .diagnostics)
        ?? [],
      attachments: try container.decodeIfPresent(
        [DiagnosticAttachment].self, forKey: .attachments) ?? [],
      status: try container.decodeIfPresent(ReportExecutionStatus.self, forKey: .status)
        ?? .passed,
      verdictCauses: try container.decodeIfPresent(
        [ReportVerdictCause].self, forKey: .verdictCauses),
      warnings: try container.decodeIfPresent([ReportWarning].self, forKey: .warnings) ?? []
    )
    if let verdict = try container.decodeIfPresent(ReportVerdict.self, forKey: .verdict) {
      self.verdict = verdict
    }
  }

  private static func makeVerdictCauses(
    scope: ReportScope,
    status: ReportExecutionStatus,
    baselines: [BaselineComparison],
    budgets: [BudgetComparison],
    diagnostics: [DiagnosticMetric]
  ) -> [ReportVerdictCause] {
    var causes: [ReportVerdictCause] = []
    if status == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .executionFailed,
          scope: scope,
          message: "Benchmark execution failed."
        )
      )
    }
    for comparison in baselines where comparison.verdict == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .baselineRegression,
          scope: scope,
          message:
            "Baseline regression for \(comparison.metric.name) \(comparison.statistic.rawValue).",
          metric: comparison.metric,
          statistic: comparison.statistic,
          actual: comparison.current,
          expected: comparison.baseline,
          delta: comparison.delta,
          percentageDelta: comparison.percentageDelta.isFinite ? comparison.percentageDelta : nil
        )
      )
    }
    for budget in budgets where budget.verdict == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .budgetExceeded,
          scope: scope,
          message:
            "Budget exceeded for \(budget.policy.metric.name) \(budget.policy.statistic.rawValue).",
          metric: budget.policy.metric,
          statistic: budget.policy.statistic,
          actual: budget.actual,
          expected: budget.policy.limit,
          delta: budget.delta,
          budget: budget.policy
        )
      )
    }
    for diagnostic in diagnostics where diagnostic.state.kind == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .diagnosticFailed,
          scope: diagnostic.scope,
          message: diagnostic.state.reason ?? "Diagnostic '\(diagnostic.name)' failed.",
          diagnosticID: diagnostic.id
        )
      )
    }
    return causes
  }
}

public struct SuiteReport: Sendable, Equatable, Codable {
  public var id: ReportID
  public var scope: ReportScope
  public var name: String
  public var cases: [CaseReport]

  public init(id: ReportID, scope: ReportScope, name: String, cases: [CaseReport]) {
    self.id = id
    self.scope = scope
    self.name = name
    self.cases = cases
  }
}

public struct ReportSummary: Sendable, Equatable, Codable {
  public var suiteCount: Int
  public var caseCount: Int
  /// Cases with at least one failed baseline comparison.
  public var failedRegressionCount: Int
  public var failedBudgetCount: Int
  public var unavailableDiagnosticCount: Int
  public var failedDiagnosticCount: Int
  /// Run warnings plus every case's warnings.
  public var warningCount: Int
  public var verdict: ReportVerdict

  public init(suites: [SuiteReport], runWarnings: [ReportWarning] = []) {
    let cases = suites.flatMap(\.cases)
    self.warningCount = runWarnings.count + cases.reduce(0) { $0 + $1.warnings.count }
    self.suiteCount = suites.count
    self.caseCount = cases.count
    self.failedRegressionCount =
      cases.filter { report in
        report.baselines.contains { $0.verdict == .failed }
      }.count
    self.failedBudgetCount = cases.reduce(0) { partial, report in
      partial + report.budgets.filter { $0.verdict == .failed }.count
    }
    self.unavailableDiagnosticCount = cases.reduce(0) { partial, report in
      partial + report.diagnostics.filter { $0.state.kind == .unavailable }.count
    }
    self.failedDiagnosticCount = cases.reduce(0) { partial, report in
      partial + report.diagnostics.filter { $0.state.kind == .failed }.count
    }
    self.verdict =
      failedRegressionCount == 0 && failedBudgetCount == 0 && failedDiagnosticCount == 0
      ? .passed : .failed
  }
}

public struct ReportDocument: Sendable, Equatable, Codable {
  public var metadata: RunMetadata
  public var suites: [SuiteReport]
  /// Conditions that make the whole run's comparisons less trustworthy.
  public var warnings: [ReportWarning]
  public var summary: ReportSummary

  public init(metadata: RunMetadata, suites: [SuiteReport], warnings: [ReportWarning] = []) {
    self.metadata = metadata
    self.suites = suites
    self.warnings = warnings
    self.summary = ReportSummary(suites: suites, runWarnings: warnings)
  }

  public init(
    metadata: RunMetadata,
    results: [BenchmarkResult],
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = []
  ) {
    let groupedResults = Dictionary(grouping: results, by: \.suiteName)
    let suites = groupedResults.keys.sorted().map { suiteName -> SuiteReport in
      let suiteID = ReportIDFactory.suite(suiteName)
      let suiteResults = (groupedResults[suiteName] ?? []).sorted { $0.caseName < $1.caseName }
      let cases = suiteResults.map { result -> CaseReport in
        let caseID = ReportIDFactory.benchmarkCase(
          suiteName: result.suiteName,
          caseName: result.caseName
        )
        let scope = ReportScope(runID: metadata.id, suiteID: suiteID, caseID: caseID)
        let measurement = ReportDocument.reportMeasurement(from: result)
        let compared = comparison.compare(
          suiteName: result.suiteName,
          caseName: result.caseName,
          scope: scope,
          measurement: measurement,
          baseline: baseline
        )
        let sourceLocation = result.sourceLocation.map(SourceLocationReport.init)

        return CaseReport(
          id: caseID,
          scope: scope,
          name: result.caseName,
          sourceLocation: sourceLocation,
          configuration: BenchmarkConfigurationReport(result.configuration),
          tags: result.tags,
          measurement: measurement,
          baselines: compared.baselines,
          budgets: compared.budgets,
          dimensionCurves: Report.DimensionCurve.curves(
            suiteName: result.suiteName,
            caseName: result.caseName,
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
        cases: cases
      )
    }

    self.init(
      metadata: metadata,
      suites: suites,
      warnings: ReportWarning.runWarnings(metadata: metadata, baseline: baseline)
    )
  }

  /// Replaces every case's baseline comparisons and budgets with the result
  /// of comparing it under `comparison`. Without a baseline, existing baseline
  /// comparisons are kept.
  public func comparing(
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default
  ) -> ReportDocument {
    let suites = self.suites.map { suite in
      let cases = suite.cases.map { report in
        let compared = comparison.compare(
          suiteName: suite.name,
          caseName: report.name,
          scope: report.scope,
          measurement: report.measurement,
          baseline: baseline
        )
        let recompared = baseline != nil || !comparison.budgets.isEmpty
        return CaseReport(
          id: report.id,
          scope: report.scope,
          name: report.name,
          sourceLocation: report.sourceLocation,
          configuration: report.configuration,
          tags: report.tags,
          measurement: report.measurement,
          baselines: baseline == nil ? report.baselines : compared.baselines,
          budgets: comparison.budgets.isEmpty ? report.budgets : compared.budgets,
          dimensionCurves: report.dimensionCurves,
          attribution: report.attribution,
          attributions: report.attributions,
          diagnostics: report.diagnostics,
          attachments: report.attachments,
          status: report.status,
          warnings: recompared ? compared.warnings : report.warnings
        )
      }
      return SuiteReport(id: suite.id, scope: suite.scope, name: suite.name, cases: cases)
    }
    return ReportDocument(
      metadata: metadata,
      suites: suites,
      warnings: baseline == nil
        ? warnings : ReportWarning.runWarnings(metadata: metadata, baseline: baseline)
    )
  }

  private static func reportMeasurement(from result: BenchmarkResult) -> Report.Measurement {
    Report.Measurement(
      rows: result.measurement.rows.map { row in
        Report.Measurement.Row(
          id: row.id,
          size: row.size,
          arguments: row.arguments,
          samples: row.samples.map { sample in
            SampleReport(
              id: ReportIDFactory.sample(
                suiteName: result.suiteName,
                caseName: result.caseName,
                size: row.size,
                rowID: row.id,
                iteration: sample.iteration
              ),
              iterationID: ReportIDFactory.iteration(
                suiteName: result.suiteName,
                caseName: result.caseName,
                size: row.size,
                rowID: row.id,
                iteration: sample.iteration
              ),
              iteration: sample.iteration,
              batchSize: sample.batchSize,
              values: Dictionary(
                uniqueKeysWithValues: sample.values.map { ($0.key.name, $0.value) })
            )
          },
          metrics: Array(Set(row.samples.flatMap(\.values.keys)))
        )
      }
    )
  }
}

extension SourceLocationReport {
  init(_ sourceLocation: BenchmarkSourceLocation) {
    self.init(
      fileID: sourceLocation.fileID,
      filePath: sourceLocation.filePath,
      line: sourceLocation.line,
      column: sourceLocation.column
    )
  }
}

extension BenchmarkConfigurationReport {
  init(_ configuration: BenchmarkConfiguration) {
    self.init(
      warmup: String(describing: configuration.warmup),
      iterations: String(describing: configuration.iterations),
      batching: String(describing: configuration.batching)
    )
  }
}
