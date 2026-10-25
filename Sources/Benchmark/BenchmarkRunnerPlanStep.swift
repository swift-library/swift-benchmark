// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

extension BenchmarkRunner.Plan {
  public struct Step: Sendable {
    public var suite: BenchmarkSuite
    public var benchmarkCase: BenchmarkCase
    public var configuration: BenchmarkConfiguration
    public var tags: [String]
    public var action: Action
    var caseRow: BenchmarkCaseRow?

    /// Identifies the step in its plan. Steps with different suite names,
    /// case names or rows have different identifiers, and a plan built from
    /// the same declarations in another process gives the step the same one.
    public var id: String {
      let suite = BenchmarkIdentifier.component(suiteName)
      let names = "benchmark:\(suite):\(BenchmarkIdentifier.component(caseName))"
      return rowID.map { "\(names):\($0)" } ?? names
    }

    public var suiteName: String {
      suite.name
    }

    public var caseName: String {
      benchmarkCase.name
    }

    public var size: Benchmark.Scale? {
      switch action {
      case .measure(let row):
        return row.scale
      case .skip, .planningFailure:
        return nil
      }
    }

    public var arguments: [Benchmark.ArgumentValue] {
      switch action {
      case .measure(let row):
        return row.arguments
      case .skip, .planningFailure:
        return []
      }
    }

    var argumentRow: Benchmark.ArgumentRow? {
      switch action {
      case .measure(let row):
        return row
      case .skip, .planningFailure:
        return nil
      }
    }

    private var rowID: String? {
      switch action {
      case .measure(let row):
        return row.id
      case .skip, .planningFailure:
        return nil
      }
    }

    init(
      suite: BenchmarkSuite,
      benchmarkCase: BenchmarkCase,
      configuration: BenchmarkConfiguration,
      tags: [String] = [],
      action: Action,
      caseRow: BenchmarkCaseRow? = nil
    ) {
      self.suite = suite
      self.benchmarkCase = benchmarkCase
      self.configuration = configuration
      self.tags = tags
      self.action = action
      self.caseRow = caseRow
    }
  }

  public enum Action: Sendable {
    case measure(Benchmark.ArgumentRow)
    case skip(reason: String)
    case planningFailure(BenchmarkPlanningIssue)
  }
}

extension BenchmarkRunner.Plan.Action {
  var isMeasure: Bool {
    if case .measure = self {
      return true
    }
    return false
  }
}

public enum BenchmarkPlanningIssue: Sendable, Equatable, CustomStringConvertible {
  case conflictingConfiguration(benchmarkName: String)
  case conflictingDimension(benchmarkName: String)
  case invalidDimension(benchmarkName: String, reason: String)
  case invalidArguments(benchmarkName: String, reason: String)

  public var description: String {
    switch self {
    case .conflictingConfiguration(let benchmarkName):
      return "Benchmark '\(benchmarkName)' has conflicting configuration traits."
    case .conflictingDimension(let benchmarkName):
      return "Benchmark '\(benchmarkName)' has conflicting Dimension traits."
    case .invalidDimension(let benchmarkName, let reason):
      return "Dimension benchmark '\(benchmarkName)' \(reason)."
    case .invalidArguments(let benchmarkName, let reason):
      return "Parameterized benchmark '\(benchmarkName)' \(reason)."
    }
  }
}
