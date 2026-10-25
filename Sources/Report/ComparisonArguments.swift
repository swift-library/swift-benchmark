// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

/// Parses the command-line options that build a ``ComparisonPolicy``.
///
/// - `--statistic <name>`: the statistic baseline comparisons use.
/// - `--threshold <value>` or `--threshold <metric>=<value>`: `10%` for a
///   relative threshold, or an absolute amount such as `500us`, `4KiB` or `2`.
/// - `--budget <metric>:<statistic>:<value>` and
///   `--case-budget <suite>:<case>:<metric>:<statistic>:<value>`.
///
/// Absolute values accept `ns`, `us`, `ms` and `s` for time, `B`, `KB`, `MB`,
/// `GB`, `KiB`, `MiB` and `GiB` for bytes, and a plain number in the metric's
/// base unit.
package enum ComparisonArguments {
  package static func policy(
    statistic: String?,
    thresholds: [String],
    budgets: [String],
    caseBudgets: [String]
  ) throws -> ComparisonPolicy {
    var policy = ComparisonPolicy()
    if let statistic {
      policy.statistic = try parseStatistic(statistic)
    }
    for value in thresholds {
      if let separator = value.firstIndex(of: "=") {
        let amount = String(value[value.index(after: separator)...])
        let metric = try parseMetric(String(value[..<separator]), amount: amount)
        policy.metricThresholds[metric] = try parseThreshold(
          amount, metric: metric, option: "--threshold")
      } else {
        guard value.hasSuffix("%") else {
          throw ComparisonArgumentError.absoluteThresholdNeedsMetric(value)
        }
        policy.threshold = try parseThreshold(value, metric: nil, option: "--threshold")
      }
    }
    policy.budgets =
      try budgets.map { value in
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
          throw ComparisonArgumentError.invalidBudget("--budget", value)
        }
        return try budget(suiteName: nil, caseName: nil, parts: parts, option: "--budget")
      }
      + caseBudgets.map { value in
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else {
          throw ComparisonArgumentError.invalidBudget("--case-budget", value)
        }
        return try budget(
          suiteName: parts[0], caseName: parts[1], parts: Array(parts[2...]),
          option: "--case-budget")
      }
    return policy
  }

  private static func budget(
    suiteName: String?,
    caseName: String?,
    parts: [String],
    option: String
  ) throws -> BudgetPolicy {
    let metric = try parseMetric(parts[0], amount: parts[2])
    return BudgetPolicy(
      suiteName: suiteName,
      caseName: caseName,
      metric: metric,
      statistic: try parseStatistic(parts[1]),
      limit: try parseAmount(parts[2], unit: metric.unit, option: option)
    )
  }

  private static func parseStatistic(_ value: String) throws -> Report.Statistic {
    guard let statistic = Report.Statistic(rawValue: value) else {
      throw ComparisonArgumentError.invalidStatistic(value)
    }
    return statistic
  }

  /// Resolves a built-in metric by name. Any other name is a custom metric
  /// whose unit follows the unit suffix of `amount`, or `count` without one.
  private static func parseMetric(_ value: String, amount: String) throws -> Benchmark.Metric {
    guard !value.isEmpty else {
      throw ComparisonArgumentError.invalidMetric(value)
    }
    if let metric = Benchmark.Metric.builtIn.first(where: { $0.name == value }) {
      return metric
    }
    let suffix = String(amount.drop { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" })
    let unit = unitScales.first { $0.value[suffix] != nil }?.key ?? .count
    return Benchmark.Metric(name: value, unit: unit)
  }

  private static let unitScales: [Benchmark.Metric.Unit: [String: Double]] = [
    .nanoseconds: ["ns": 1, "us": 1_000, "µs": 1_000, "ms": 1_000_000, "s": 1_000_000_000],
    .bytes: [
      "B": 1, "KB": 1_000, "MB": 1_000_000, "GB": 1_000_000_000,
      "KiB": 1_024, "MiB": 1_048_576, "GiB": 1_073_741_824,
    ],
  ]

  private static func parseThreshold(
    _ value: String,
    metric: Benchmark.Metric?,
    option: String
  ) throws -> ThresholdPolicy {
    if value.hasSuffix("%") {
      guard let percentage = Double(value.dropLast()), percentage >= 0 else {
        throw ComparisonArgumentError.invalidNumber(option, value)
      }
      return .relativePercentage(percentage)
    }
    guard let metric else {
      throw ComparisonArgumentError.absoluteThresholdNeedsMetric(value)
    }
    return .absolute(try parseAmount(value, unit: metric.unit, option: option))
  }

  private static func parseAmount(
    _ value: String,
    unit: Benchmark.Metric.Unit,
    option: String
  ) throws -> Double {
    let suffixStart =
      value.firstIndex { !($0.isNumber || $0 == "." || $0 == "-" || $0 == "+") } ?? value.endIndex
    guard let number = Double(value[..<suffixStart]) else {
      throw ComparisonArgumentError.invalidNumber(option, value)
    }
    let suffix = String(value[suffixStart...])
    guard !suffix.isEmpty else {
      return number
    }
    guard let scale = unitScales[unit]?[suffix] else {
      throw ComparisonArgumentError.unitMismatch(option, value, unit)
    }
    return number * scale
  }
}

package enum ComparisonArgumentError: Error, CustomStringConvertible, Equatable {
  case invalidStatistic(String)
  case invalidMetric(String)
  case invalidNumber(String, String)
  case invalidBudget(String, String)
  case absoluteThresholdNeedsMetric(String)
  case unitMismatch(String, String, Benchmark.Metric.Unit)

  package var description: String {
    switch self {
    case .invalidStatistic(let value):
      return
        "Unknown statistic '\(value)'. Use one of: \(Report.Statistic.allCases.map(\.rawValue).joined(separator: ", "))."
    case .invalidMetric(let value):
      return "Invalid metric name '\(value)'."
    case .invalidNumber(let option, let value):
      return "\(option) expects a number, got '\(value)'."
    case .invalidBudget(let option, let value):
      return option == "--budget"
        ? "--budget expects <metric>:<statistic>:<value>, got '\(value)'."
        : "--case-budget expects <suite>:<case>:<metric>:<statistic>:<value>, got '\(value)'."
    case .absoluteThresholdNeedsMetric(let value):
      return "An absolute threshold needs a metric, as in --threshold wallClock=\(value)."
    case .unitMismatch(let option, let value, let unit):
      return "\(option) value '\(value)' has a unit that does not apply to \(unit.rawValue)."
    }
  }
}
