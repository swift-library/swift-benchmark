// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

public enum ReportVerdict: String, Sendable, Codable {
  case passed
  case failed
  case notCompared
}

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

/// The measurements a baseline file stores for one case.
public struct BaselineCase: Sendable, Equatable, Codable {
  /// The suite the case belongs to.
  public var suiteName: String
  /// The case's name.
  public var caseName: String
  /// The case's recorded samples and statistics.
  public var measurement: Report.Measurement

  /// Creates a baseline entry for one case.
  public init(suiteName: String, caseName: String, measurement: Report.Measurement) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.measurement = measurement
  }
}

/// A baseline file: the measurements of an earlier run to compare with.
public struct BaselineDocument: Sendable, Equatable, Codable {
  /// The conditions the baseline was recorded under, compared with the run's.
  public var metadata: RunMetadata?
  public var cases: [BaselineCase]

  /// Creates a baseline from cases and the conditions they were recorded under.
  public init(metadata: RunMetadata? = nil, cases: [BaselineCase]) {
    self.metadata = metadata
    self.cases = cases
  }

  /// A baseline holding every case of `document`.
  public init(document: ReportDocument) {
    self.init(
      metadata: document.metadata,
      cases: document.suites.flatMap { suite in
        suite.cases.map { report in
          BaselineCase(
            suiteName: suite.name,
            caseName: report.name,
            measurement: report.measurement
          )
        }
      }
    )
  }

  public func baselineCase(suiteName: String, caseName: String) -> BaselineCase? {
    cases.first { baseline in
      baseline.suiteName == suiteName && baseline.caseName == caseName
    }
  }

  /// Reads a baseline JSON file written by the `baseline write` command.
  package static func read(path: String) throws -> BaselineDocument {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    do {
      return try JSONDecoder().decode(BaselineDocument.self, from: data)
    } catch is DecodingError {
      throw BaselineReadError.unreadable(path: path)
    }
  }
}

package enum BaselineReadError: Error, CustomStringConvertible, Equatable {
  case unreadable(path: String)

  package var description: String {
    switch self {
    case .unreadable(let path):
      return
        "'\(path)' is not a baseline this swift-benchmark can read. Record it again with the baseline write command."
    }
  }
}

/// The comparison of one metric of one row between a run and its baseline.
public struct BaselineComparison: Sendable, Equatable, Codable {
  /// The metric this applies to.
  public var metric: Benchmark.Metric
  /// The statistic of the metric this applies to.
  public var statistic: Report.Statistic
  /// The row's Dimension size, if it has one.
  public var size: Benchmark.Scale?
  /// The row's argument row identifier, if it has one.
  public var rowID: String?
  /// The statistic's value in this run, in the metric's unit.
  public var current: Double
  /// The statistic's value in the baseline, in the metric's unit.
  public var baseline: Double
  /// `current - baseline`, in the metric's unit.
  public var delta: Double
  /// `delta` as a percentage of `baseline`; infinite when the baseline is zero.
  public var percentageDelta: Double
  public var threshold: ThresholdPolicy
  public var verdict: ReportVerdict

  /// Compares `current` with `baseline`. A change in the metric's better
  /// direction always passes; a change in its worse direction passes while it
  /// stays within `threshold`.
  public init(
    metric: Benchmark.Metric,
    statistic: Report.Statistic,
    current: Double,
    baseline: Double,
    threshold: ThresholdPolicy,
    size: Benchmark.Scale? = nil,
    rowID: String? = nil
  ) {
    self.metric = metric
    self.statistic = statistic
    self.size = size
    self.rowID = rowID
    self.current = current
    self.baseline = baseline
    self.delta = current - baseline
    if baseline == 0 {
      self.percentageDelta = delta == 0 ? 0 : (delta < 0 ? -.infinity : .infinity)
    } else {
      self.percentageDelta = delta / abs(baseline) * 100
    }
    self.threshold = threshold
    let worsening = metric.direction == .lowerIsBetter ? delta : -delta
    if worsening <= 0 {
      self.verdict = .passed
    } else {
      switch threshold.kind {
      case .relativePercentage:
        let worseningPercentage = baseline == 0 ? Double.infinity : worsening / abs(baseline) * 100
        self.verdict = worseningPercentage <= threshold.value ? .passed : .failed
      case .absolute:
        self.verdict = worsening <= threshold.value ? .passed : .failed
      }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case metric
    case statistic
    case size
    case rowID
    case current
    case baseline
    case delta
    case percentageDelta
    case threshold
    case verdict
  }

  /// Decodes a comparison. A `null` percentage delta comes from a zero baseline
  /// and decodes as an infinite delta with the sign of `delta`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    metric = try container.decode(Benchmark.Metric.self, forKey: .metric)
    statistic = try container.decode(Report.Statistic.self, forKey: .statistic)
    size = try container.decodeIfPresent(Benchmark.Scale.self, forKey: .size)
    rowID = try container.decodeIfPresent(String.self, forKey: .rowID)
    current = try container.decode(Double.self, forKey: .current)
    baseline = try container.decode(Double.self, forKey: .baseline)
    delta = try container.decode(Double.self, forKey: .delta)
    percentageDelta =
      try container.decodeIfPresent(Double.self, forKey: .percentageDelta)
      ?? (delta < 0 ? -.infinity : .infinity)
    threshold = try container.decode(ThresholdPolicy.self, forKey: .threshold)
    verdict = try container.decode(ReportVerdict.self, forKey: .verdict)
  }

  /// Encodes a comparison. JSON has no infinity, so the infinite percentage
  /// delta of a zero baseline is encoded as `null`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(metric, forKey: .metric)
    try container.encode(statistic, forKey: .statistic)
    try container.encodeIfPresent(size, forKey: .size)
    try container.encodeIfPresent(rowID, forKey: .rowID)
    try container.encode(current, forKey: .current)
    try container.encode(baseline, forKey: .baseline)
    try container.encode(delta, forKey: .delta)
    if percentageDelta.isFinite {
      try container.encode(percentageDelta, forKey: .percentageDelta)
    } else {
      try container.encodeNil(forKey: .percentageDelta)
    }
    try container.encode(threshold, forKey: .threshold)
    try container.encode(verdict, forKey: .verdict)
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

/// The evaluation of one budget on one measurement row.
public struct BudgetComparison: Sendable, Equatable, Codable {
  public var policy: BudgetPolicy
  /// The row's Dimension size, if it has one.
  public var size: Benchmark.Scale?
  /// The row's argument row identifier, if it has one.
  public var rowID: String?
  /// The measured statistic, or `nil` when the row has no values for the metric.
  public var actual: Double?
  /// `actual - limit`, in the metric's unit.
  public var delta: Double?
  /// `notCompared` when the row has no values for the budget's metric.
  public var verdict: ReportVerdict

  /// Evaluates `policy` on `row`, using the row's own description of the metric.
  public init(policy: BudgetPolicy, row: Report.Measurement.Row) {
    self.policy = policy
    self.size = row.size
    self.rowID = row.id
    guard let measured = row.metrics.first(where: { $0 == policy.metric }),
      let statistics = row.statistics(for: measured)
    else {
      self.actual = nil
      self.delta = nil
      self.verdict = .notCompared
      return
    }
    let actual = policy.statistic.value(from: statistics)
    self.actual = actual
    self.delta = actual - policy.limit
    let withinLimit =
      measured.direction == .lowerIsBetter ? actual <= policy.limit : actual >= policy.limit
    self.verdict = withinLimit ? .passed : .failed
  }
}
