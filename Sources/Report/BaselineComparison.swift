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
    case relativePercentage
    /// An absolute amount in the compared metric's unit.
    case absolute
  }

  public var kind: Kind
  public var value: Double

  public init(kind: Kind, value: Double) {
    self.kind = kind
    self.value = value
  }

  public static func relativePercentage(_ percentage: Double) -> ThresholdPolicy {
    ThresholdPolicy(kind: .relativePercentage, value: percentage)
  }

  public static func absolute(_ value: Double) -> ThresholdPolicy {
    ThresholdPolicy(kind: .absolute, value: value)
  }
}

/// The rules for comparing a run with a baseline and with budgets.
public struct ComparisonPolicy: Sendable, Equatable {
  public static let `default` = ComparisonPolicy()

  /// The statistic baseline comparisons use for every metric.
  public var statistic: Report.Statistic
  /// The threshold for metrics without an entry in ``metricThresholds``.
  public var threshold: ThresholdPolicy
  public var metricThresholds: [Benchmark.Metric: ThresholdPolicy]
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

  public func threshold(for metric: Benchmark.Metric) -> ThresholdPolicy {
    metricThresholds.first { $0.key.name == metric.name }?.value ?? threshold
  }

  /// Compares every metric that both the measurement and its baseline case
  /// have, evaluates the budgets that apply to the case, and warns about
  /// comparisons that noise or too few samples make unreliable.
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
    var baselines: [BaselineComparison] = []
    if let baselineCase {
      for metric in measurement.metrics {
        guard let current = measurement.statistics(for: metric),
          let previous = baselineCase.measurement.statistics(for: metric)
        else {
          continue
        }
        baselines.append(
          BaselineComparison(
            metric: metric,
            statistic: statistic,
            current: statistic.value(from: current),
            baseline: statistic.value(from: previous),
            threshold: threshold(for: metric)
          )
        )
      }
    }
    let budgetComparisons =
      budgets
      .filter { $0.applies(suiteName: suiteName, caseName: caseName) }
      .map { BudgetComparison(policy: $0, measurement: measurement) }
    let isCompared = !baselines.isEmpty || budgetComparisons.contains { $0.verdict != .notCompared }
    let warnings =
      isCompared
      ? ReportWarning.comparisonWarnings(
        scope: scope,
        measurement: measurement,
        baseline: baselineCase?.measurement,
        comparisons: baselines
      ) : []
    return (baselines, budgetComparisons, warnings)
  }
}

public struct BaselineCase: Sendable, Equatable, Codable {
  public var suiteName: String
  public var caseName: String
  public var measurement: Report.Measurement

  public init(suiteName: String, caseName: String, measurement: Report.Measurement) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.measurement = measurement
  }
}

public struct BaselineDocument: Sendable, Equatable, Codable {
  public var metadata: RunMetadata?
  public var cases: [BaselineCase]

  public init(metadata: RunMetadata? = nil, cases: [BaselineCase]) {
    self.metadata = metadata
    self.cases = cases
  }

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

/// The comparison of one metric between a run and its baseline.
public struct BaselineComparison: Sendable, Equatable, Codable {
  public var metric: Benchmark.Metric
  public var statistic: Report.Statistic
  public var current: Double
  public var baseline: Double
  /// `current - baseline`, in the metric's unit.
  public var delta: Double
  /// `delta` as a percentage of `baseline`; infinite when the baseline is zero.
  public var percentageDelta: Double
  public var threshold: ThresholdPolicy
  public var verdict: ReportVerdict

  public init(
    metric: Benchmark.Metric,
    statistic: Report.Statistic,
    current: Double,
    baseline: Double,
    threshold: ThresholdPolicy
  ) {
    self.metric = metric
    self.statistic = statistic
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
/// The limit is an upper bound for metrics where lower is better and a lower
/// bound for metrics where higher is better.
public struct BudgetPolicy: Sendable, Equatable, Codable {
  public var suiteName: String?
  public var caseName: String?
  public var metric: Benchmark.Metric
  public var statistic: Report.Statistic
  /// The limit in the metric's unit.
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

public struct BudgetComparison: Sendable, Equatable, Codable {
  public var policy: BudgetPolicy
  /// The measured statistic, or `nil` when the case has no values for the metric.
  public var actual: Double?
  /// `actual - limit`, in the metric's unit.
  public var delta: Double?
  /// `notCompared` when the case has no values for the budget's metric.
  public var verdict: ReportVerdict

  public init(policy: BudgetPolicy, measurement: Report.Measurement) {
    self.policy = policy
    guard let statistics = measurement.statistics(for: policy.metric) else {
      self.actual = nil
      self.delta = nil
      self.verdict = .notCompared
      return
    }
    let actual = policy.statistic.value(from: statistics)
    self.actual = actual
    self.delta = actual - policy.limit
    let withinLimit =
      policy.metric.direction == .lowerIsBetter ? actual <= policy.limit : actual >= policy.limit
    self.verdict = withinLimit ? .passed : .failed
  }
}
