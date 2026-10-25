// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

public enum ReportVerdict: String, Sendable, Codable {
  case passed
  case failed
  case notCompared
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
