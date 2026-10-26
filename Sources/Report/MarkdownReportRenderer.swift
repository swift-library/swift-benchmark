// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

/// Renders a report as GitHub Markdown for pull request comments: the
/// verdict, warnings, then a table of baseline comparisons, or of medians
/// without a baseline, failed budgets, allocation sites and complexity fits. JSON stays the
/// report's data format; this layout can change.
package enum MarkdownReportRenderer {
  package static func render(_ document: ReportDocument) -> String {
    let summary = document.summary
    let cases = document.suites.flatMap { suite in suite.cases.map { (suite, $0) } }
    var lines = [
      "## Benchmark report: \(summary.verdict.rawValue)",
      "",
      "\(summary.caseCount) case(s) in \(summary.suiteCount) suite(s) · \(summary.failedRegressionCount) regression(s) · \(summary.failedBudgetCount) failed budget(s) · \(summary.warningCount) warning(s)",
    ]

    let warnings =
      document.warnings.map(\.message)
      + cases.flatMap { suite, report in
        report.warnings.map { "\(caseName(suite, report)): \($0.message)" }
      }
    if !warnings.isEmpty {
      lines += ["", "> [!WARNING]"] + warnings.map { "> - \(escaped($0))" }
    }

    let comparisons = cases.flatMap { suite, report in
      report.baselines.map { (suite, report, $0) }
    }
    if comparisons.isEmpty {
      lines += [
        "", "### Measurements", "",
        "| Case | Row | Metric | Median | p95 |",
        "| --- | --- | --- | ---: | ---: |",
      ]
      for (suite, report) in cases {
        for row in report.measurement.rows {
          for metric in row.metrics {
            guard let statistics = row.statistics(for: metric) else {
              continue
            }
            lines.append(
              "| \(escaped(caseName(suite, report))) | \(escaped(row.label ?? "")) | \(metric.name) | \(formatValue(statistics.median, unit: metric.unit)) | \(formatValue(statistics.p95, unit: metric.unit)) |"
            )
          }
        }
      }
    } else {
      lines += [
        "", "### Comparisons with the baseline", "",
        "| Case | Row | Metric | Baseline | Current | Change | 95% interval | Verdict |",
        "| --- | --- | --- | ---: | ---: | ---: | --- | --- |",
      ]
      for (suite, report, comparison) in comparisons {
        let row = report.measurement.rows.first {
          $0.id == comparison.rowID && $0.size == comparison.size
        }
        let verdict =
          comparison.verdict == .failed ? "**failed**" : comparison.verdict.rawValue
        lines.append(
          "| \(escaped(caseName(suite, report))) | \(escaped(row?.label ?? "")) | \(comparison.metric.name) \(comparison.statistic.rawValue) | \(formatValue(comparison.baseline, unit: comparison.metric.unit)) | \(formatValue(comparison.current, unit: comparison.metric.unit)) | \(change(comparison.delta, of: comparison.baseline, unit: comparison.metric.unit)) | \(interval(comparison)) | \(verdict) |"
        )
      }
    }

    let failedBudgets = cases.flatMap { suite, report in
      report.budgets.filter { $0.verdict == .failed }.map { (suite, report, $0) }
    }
    if !failedBudgets.isEmpty {
      lines += ["", "### Failed budgets", ""]
      for (suite, report, budget) in failedBudgets {
        let metric = budget.policy.metric
        let actual = budget.actual.map { formatValue($0, unit: metric.unit) } ?? "none"
        lines.append(
          "- \(escaped(caseName(suite, report))): \(metric.name) \(budget.policy.statistic.rawValue) \(actual), limit \(formatValue(budget.policy.limit, unit: metric.unit))"
        )
      }
    }

    let siteRows = cases.flatMap { suite, report in
      report.measurement.rows.compactMap { row in
        row.allocationSites.map { (suite, report, row, $0) }
      }
    }
    if !siteRows.isEmpty {
      lines += [
        "", "### Allocation sites", "",
        "| Case | Row | Allocations per call | Bytes per call | Site |",
        "| --- | --- | ---: | ---: | --- |",
      ]
      for (suite, report, row, sites) in siteRows {
        for stack in sites.stacks.prefix(3) {
          lines.append(
            "| \(escaped(caseName(suite, report))) | \(escaped(row.label ?? "")) | \(formatValue(stack.allocationsPerCall(of: sites), unit: .count)) | \(formatValue(stack.bytesPerCall(of: sites), unit: .bytes)) | \(escaped(stack.summary())) |"
          )
        }
      }
    }

    let fits = cases.flatMap { suite, report in
      report.dimensionCurves.filter { $0.statistic == .median }.compactMap { curve in
        curve.complexity.map { (suite, report, curve, $0) }
      }
    }
    if !fits.isEmpty {
      lines += [
        "", "### Complexity", "",
        "| Case | Metric | Model | Fit error |",
        "| --- | --- | --- | ---: |",
      ]
      for (suite, report, curve, complexity) in fits {
        lines.append(
          "| \(escaped(caseName(suite, report))) | \(curve.metric.name) | \(complexity.model.notation) | \(String(format: "%.1f%%", complexity.normalizedRMS * 100)) |"
        )
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private static func caseName(_ suite: SuiteReport, _ report: CaseReport) -> String {
    "\(suite.name) › \(report.name)"
  }

  /// `delta` as a percentage of `baseline`, or in the metric's unit when the
  /// baseline is zero.
  private static func change(_ delta: Double, of baseline: Double, unit: Benchmark.Metric.Unit)
    -> String
  {
    guard baseline != 0 else {
      return signed(formatValue(delta, unit: unit), delta)
    }
    return signed(String(format: "%.1f%%", abs(delta / baseline * 100)), delta)
  }

  private static func interval(_ comparison: BaselineComparison) -> String {
    guard let interval = comparison.confidenceInterval else {
      return "—"
    }
    let unit = comparison.metric.unit
    let bounds = [interval.lowerBound, interval.upperBound].map {
      change($0, of: comparison.baseline, unit: unit)
    }
    return "\(bounds[0]) to \(bounds[1])"
  }

  private static func signed(_ magnitude: String, _ value: Double) -> String {
    let unsigned = magnitude.replacingOccurrences(of: "-", with: "")
    if value > 0 {
      return "+\(unsigned)"
    }
    if value < 0 {
      return "−\(unsigned)"
    }
    return unsigned
  }

  private static func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "|", with: "\\|")
  }
}
