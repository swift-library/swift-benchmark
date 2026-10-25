// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

/// How far a metric may move in its worse direction before a baseline
/// comparison fails.
public struct ThresholdPolicy: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    /// A percentage of the baseline value.
    case relativePercentage
    /// An absolute amount in the compared metric's unit.
    case absolute
  }

  public var kind: Kind
  /// The percentage or the absolute amount, depending on ``kind``.
  public var value: Double

  public init(kind: Kind, value: Double) {
    self.kind = kind
    self.value = value
  }

  /// Allows the metric to worsen by `percentage` percent of its baseline value.
  public static func relativePercentage(_ percentage: Double) -> ThresholdPolicy {
    ThresholdPolicy(kind: .relativePercentage, value: percentage)
  }

  /// Allows the metric to worsen by `value`, in the metric's unit.
  public static func absolute(_ value: Double) -> ThresholdPolicy {
    ThresholdPolicy(kind: .absolute, value: value)
  }
}

/// The rules for comparing a run with a baseline and with budgets.
///
/// Comparisons are made per measurement row, so each Dimension size or
/// argument row of a case is compared with the same row of its baseline.
/// Thresholds and budgets name metrics by name; their amounts are in the
/// measured metric's unit, and the measured metric's direction decides which
/// change is a regression.
public struct ComparisonPolicy: Sendable, Equatable {
  /// Medians, a 10% threshold and no budgets.
  public static let `default` = ComparisonPolicy()

  /// The statistic baseline comparisons use for every metric.
  public var statistic: Report.Statistic
  /// The threshold for metrics without an entry in ``metricThresholds``.
  public var threshold: ThresholdPolicy
  /// Thresholds for individual metrics, matched by metric name.
  public var metricThresholds: [Benchmark.Metric: ThresholdPolicy]
  /// Limits on individual metrics, applied to every row of the cases they match.
  public var budgets: [BudgetPolicy]

  public init(
    statistic: Report.Statistic = .median,
    threshold: ThresholdPolicy = .relativePercentage(10),
    metricThresholds: [Benchmark.Metric: ThresholdPolicy] = [:],
    budgets: [BudgetPolicy] = []
  ) {
    self.statistic = statistic
    self.threshold = threshold
    self.metricThresholds = metricThresholds
    self.budgets = budgets
  }

  /// The threshold that applies to `metric`: its entry in
  /// ``metricThresholds``, or ``threshold``.
  public func threshold(for metric: Benchmark.Metric) -> ThresholdPolicy {
    metricThresholds[metric] ?? threshold
  }

  /// Compares each row with the same row of the baseline on every metric both
  /// measured, evaluates the budgets that apply to the case on each row, and
  /// warns about rows whose comparisons noise or too few samples make
  /// unreliable.
  func compare(
    suiteName: String,
    caseName: String,
    scope: ReportScope,
    measurement: Report.Measurement,
    baseline: BaselineDocument?
  ) -> (
    baselines: [BaselineComparison], budgets: [BudgetComparison], warnings: [ReportWarning]
  ) {
    let baselineCase = baseline?.baselineCase(suiteName: suiteName, caseName: caseName)
    let caseBudgets = budgets.filter { $0.applies(suiteName: suiteName, caseName: caseName) }
    var baselines: [BaselineComparison] = []
    var budgetComparisons: [BudgetComparison] = []
    var warnings: [ReportWarning] = []
    for row in measurement.rows {
      let baselineRow = baselineCase?.measurement.rows.first { $0.matches(row) }
      var rowComparisons: [BaselineComparison] = []
      if let baselineRow {
        for metric in row.metrics {
          guard let current = row.statistics(for: metric),
            let previous = baselineRow.statistics(for: metric)
          else {
            continue
          }
          rowComparisons.append(
            BaselineComparison(
              metric: metric,
              statistic: statistic,
              current: statistic.value(from: current),
              baseline: statistic.value(from: previous),
              threshold: threshold(for: metric),
              size: row.size,
              rowID: row.id
            )
          )
        }
      }
      let rowBudgets = caseBudgets.map { BudgetComparison(policy: $0, row: row) }
      if !rowComparisons.isEmpty || rowBudgets.contains(where: { $0.verdict != .notCompared }) {
        warnings += ReportWarning.rowWarnings(
          scope: scope, row: row, baselineRow: baselineRow, comparisons: rowComparisons)
      }
      baselines += rowComparisons
      budgetComparisons += rowBudgets
    }
    return (baselines, budgetComparisons, warnings)
  }
}

extension Report.Measurement.Row {
  /// Whether `other` measures the same Dimension size and argument row.
  func matches(_ other: Report.Measurement.Row) -> Bool {
    id == other.id && size == other.size
  }

  /// A short name for the row in messages, or `nil` for a case's only row.
  var label: String? {
    if let size {
      return "size \(size.rawValue)"
    }
    if !arguments.isEmpty {
      return "arguments \(arguments.map(\.label).joined(separator: ", "))"
    }
    return id
  }
}

/// A limit on one statistic of one metric, optionally scoped to a suite or case.
///
/// The metric is matched to the measured metrics by name, the limit is in the
/// measured metric's unit, and the measured metric's direction decides which
/// side of the limit fails: it is an upper bound for metrics where lower is
/// better and a lower bound for metrics where higher is better.
public struct BudgetPolicy: Sendable, Equatable, Codable {
  public var suiteName: String?
  public var caseName: String?
  /// The metric this applies to.
  public var metric: Benchmark.Metric
  /// The statistic of the metric this applies to.
  public var statistic: Report.Statistic
  /// The limit in the measured metric's unit.
  public var limit: Double

  public init(
    suiteName: String? = nil,
    caseName: String? = nil,
    metric: Benchmark.Metric,
    statistic: Report.Statistic,
    limit: Double
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.metric = metric
    self.statistic = statistic
    self.limit = limit
  }

  /// Whether the budget's suite and case filters match.
  public func applies(suiteName: String, caseName: String) -> Bool {
    if let suiteNameFilter = self.suiteName, suiteNameFilter != suiteName {
      return false
    }
    if let caseNameFilter = self.caseName, caseNameFilter != caseName {
      return false
    }
    return true
  }
}
