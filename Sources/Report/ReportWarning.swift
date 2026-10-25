// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

/// A condition that makes a report's comparisons less trustworthy without
/// failing them.
public struct ReportWarning: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    /// The baseline was recorded under different run conditions.
    case runConditionMismatch
    /// The run measured a debug build.
    case debugBuild
    /// A compared metric varies as much as its threshold allows, so the
    /// verdict can change between runs of the same code.
    case noisyComparison
    /// A compared case has fewer timed samples than a stable comparison needs.
    case fewSamples
  }

  public var kind: Kind
  public var scope: ReportScope
  public var message: String
  public var metric: Benchmark.Metric?

  public init(kind: Kind, scope: ReportScope, message: String, metric: Benchmark.Metric? = nil) {
    self.kind = kind
    self.scope = scope
    self.message = message
    self.metric = metric
  }
}

extension ReportWarning {
  /// The fewest timed samples a compared case should have.
  static let minimumTimedSamples = 5

  /// Warnings that apply to the whole run: a debug build, and a baseline
  /// recorded under different run conditions.
  static func runWarnings(metadata: RunMetadata, baseline: BaselineDocument?) -> [ReportWarning] {
    let scope = ReportScope(runID: metadata.id)
    var warnings: [ReportWarning] = []
    if metadata.buildConfiguration == "debug" {
      warnings.append(
        ReportWarning(
          kind: .debugBuild,
          scope: scope,
          message:
            "This run measured a debug build; its times and counts do not represent release performance."
        )
      )
    }
    if let previous = baseline?.metadata {
      let differences = runConditionDifferences(current: metadata, baseline: previous)
      if !differences.isEmpty {
        warnings.append(
          ReportWarning(
            kind: .runConditionMismatch,
            scope: scope,
            message:
              "The baseline was recorded under different conditions: \(differences.joined(separator: "; "))."
          )
        )
      }
    }
    return warnings
  }

  /// Warnings for one compared case: too few timed samples, and comparisons
  /// whose noise reaches their threshold.
  static func comparisonWarnings(
    scope: ReportScope,
    measurement: Report.Measurement,
    baseline: Report.Measurement?,
    comparisons: [BaselineComparison]
  ) -> [ReportWarning] {
    var warnings: [ReportWarning] = []
    if let wallClock = measurement.statistics(for: .wallClock),
      wallClock.count < minimumTimedSamples
    {
      warnings.append(
        ReportWarning(
          kind: .fewSamples,
          scope: scope,
          message:
            "Only \(wallClock.count) timed sample(s); use at least \(minimumTimedSamples) for a stable comparison.",
          metric: .wallClock
        )
      )
    }
    for comparison in comparisons {
      let spreads = [
        measurement.statistics(for: comparison.metric),
        baseline?.statistics(for: comparison.metric),
      ]
      .compactMap { $0 }
      .map { spread($0, threshold: comparison.threshold) }
      guard let worst = spreads.max(), worst > 0, worst >= comparison.threshold.value else {
        continue
      }
      warnings.append(
        ReportWarning(
          kind: .noisyComparison,
          scope: scope,
          message:
            "\(comparison.metric.name) varies by \(describe(worst, threshold: comparison.threshold)), as much as its threshold allows; the verdict may change between runs.",
          metric: comparison.metric
        )
      )
    }
    return warnings
  }

  /// A statistics' spread in the threshold's terms: the coefficient of
  /// variation in percent for a relative threshold, the standard deviation
  /// for an absolute one.
  private static func spread(_ statistics: Report.Statistics, threshold: ThresholdPolicy) -> Double
  {
    switch threshold.kind {
    case .relativePercentage:
      return statistics.mean == 0 ? 0 : statistics.standardDeviation / abs(statistics.mean) * 100
    case .absolute:
      return statistics.standardDeviation
    }
  }

  private static func describe(_ spread: Double, threshold: ThresholdPolicy) -> String {
    switch threshold.kind {
    case .relativePercentage:
      return "\(Int(spread.rounded()))% of its mean (threshold \(threshold.value)%)"
    case .absolute:
      return "a standard deviation of \(spread) (threshold \(threshold.value))"
    }
  }

  private static func runConditionDifferences(current: RunMetadata, baseline: RunMetadata)
    -> [String]
  {
    let fields: [(String, String?, String?)] = [
      ("platform", baseline.platform, current.platform),
      ("OS version", baseline.osVersion, current.osVersion),
      ("architecture", baseline.architecture, current.architecture),
      ("device", baseline.device, current.device),
      ("Swift version", baseline.swiftVersion, current.swiftVersion),
      ("build configuration", baseline.buildConfiguration, current.buildConfiguration),
    ]
    return fields.compactMap { name, previous, now in
      guard let previous, let now, previous != now else {
        return nil
      }
      return "\(name) \(previous) → \(now)"
    }
  }
}
