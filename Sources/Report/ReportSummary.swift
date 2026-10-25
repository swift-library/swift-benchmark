// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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
  /// Run warnings plus every case's warnings.
  public var warningCount: Int
  public var verdict: ReportVerdict

  /// Summarizes `suites` and the run's own warnings.
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
    self.verdict = failedRegressionCount == 0 && failedBudgetCount == 0 ? .passed : .failed
  }
}
