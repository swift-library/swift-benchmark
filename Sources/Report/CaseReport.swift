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
  }

  public var kind: Kind
  public var scope: ReportScope
  public var message: String
  /// The metric the cause is about, if any.
  public var metric: Benchmark.Metric?
  /// The statistic the cause is about, if any.
  public var statistic: Report.Statistic?
  /// The Dimension size of the row the cause is about, if it has one.
  public var size: Benchmark.Scale?
  /// The argument row identifier of the row the cause is about, if it has one.
  public var rowID: String?
  /// The measured value, in the metric's unit.
  public var actual: Double?
  /// The baseline value or budget limit, in the metric's unit.
  public var expected: Double?
  /// `actual - expected`, in the metric's unit.
  public var delta: Double?
  public var percentageDelta: Double?
  public var budget: BudgetPolicy?

  public init(
    kind: Kind,
    scope: ReportScope,
    message: String,
    metric: Benchmark.Metric? = nil,
    statistic: Report.Statistic? = nil,
    size: Benchmark.Scale? = nil,
    rowID: String? = nil,
    actual: Double? = nil,
    expected: Double? = nil,
    delta: Double? = nil,
    percentageDelta: Double? = nil,
    budget: BudgetPolicy? = nil
  ) {
    self.kind = kind
    self.scope = scope
    self.message = message
    self.metric = metric
    self.statistic = statistic
    self.size = size
    self.rowID = rowID
    self.actual = actual
    self.expected = expected
    self.delta = delta
    self.percentageDelta = percentageDelta
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
    self.attachments = attachments
    self.status = status
    self.warnings = warnings
    self.verdictCauses =
      verdictCauses
      ?? CaseReport.makeVerdictCauses(
        scope: scope,
        status: status,
        baselines: baselines,
        budgets: budgets
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

  private static func rowSuffix(size: Benchmark.Scale?, rowID: String?) -> String {
    if let size {
      return " at size \(size.rawValue)"
    }
    if let rowID {
      return " for \(rowID)"
    }
    return ""
  }

  private static func makeVerdictCauses(
    scope: ReportScope,
    status: ReportExecutionStatus,
    baselines: [BaselineComparison],
    budgets: [BudgetComparison]
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
            "Baseline regression for \(comparison.metric.name) \(comparison.statistic.rawValue)\(rowSuffix(size: comparison.size, rowID: comparison.rowID)).",
          metric: comparison.metric,
          statistic: comparison.statistic,
          size: comparison.size,
          rowID: comparison.rowID,
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
            "Budget exceeded for \(budget.policy.metric.name) \(budget.policy.statistic.rawValue)\(rowSuffix(size: budget.size, rowID: budget.rowID)).",
          metric: budget.policy.metric,
          statistic: budget.policy.statistic,
          size: budget.size,
          rowID: budget.rowID,
          actual: budget.actual,
          expected: budget.policy.limit,
          delta: budget.delta,
          budget: budget.policy
        )
      )
    }
    return causes
  }
}
