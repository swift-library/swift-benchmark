// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

extension BenchmarkRunner {
  public struct Plan: Sendable {
    public var steps: [Step]

    public init(
      suites: [BenchmarkSuite],
      filter: Filter = .all
    ) throws {
      var steps: [Step] = []
      for suite in suites {
        let suiteTraits = EffectiveSuiteTraits(suite: suite)
        guard filter.matchesSuite(suite.name) else {
          continue
        }
        for benchmarkCase in suite.cases {
          let resolved = ResolvedCase(
            suite: suite, suiteTraits: suiteTraits, benchmarkCase: benchmarkCase)
          guard filter.matchesCase(benchmarkCase.name),
            filter.matchesTags(resolved.tags)
          else {
            continue
          }

          if let issue = resolved.issue {
            steps.append(
              Step(
                suite: suite,
                benchmarkCase: benchmarkCase,
                configuration: resolved.configuration,
                tags: resolved.tags,
                action: .planningFailure(issue)
              )
            )
            continue
          }

          if let skipReason = resolved.skipReason {
            steps.append(
              Step(
                suite: suite,
                benchmarkCase: benchmarkCase,
                configuration: resolved.configuration,
                tags: resolved.tags,
                action: .skip(reason: skipReason)
              )
            )
            continue
          }

          let rowActions = Self.measurementRows(for: resolved)
          for planned in rowActions {
            steps.append(
              Step(
                suite: suite,
                benchmarkCase: benchmarkCase,
                configuration: resolved.configuration,
                tags: resolved.tags,
                action: planned.action,
                caseRow: planned.caseRow
              )
            )
          }
        }
      }
      self.steps = steps
    }

    private static func measurementRows(for resolved: ResolvedCase) -> [PlannedAction] {
      if let rows = resolved.parameterizedRows {
        guard !rows.isEmpty else {
          return [
            .action(
              .planningFailure(
                .invalidArguments(
                  benchmarkName: resolved.caseName, reason: "requires at least one argument")))
          ]
        }
        if let invalid = rows.first(where: { ($0.metadata.scale?.rawValue ?? 1) <= 0 }) {
          return [
            .action(
              .planningFailure(
                .invalidDimension(
                  benchmarkName: resolved.caseName,
                  reason: "has invalid scale \(invalid.metadata.scale?.rawValue ?? 0)"
                )
              ))
          ]
        }
        return rows.map { .measure($0) }
      }

      guard let dimension = resolved.dimension else {
        return [
          .measure(
            BenchmarkCaseRow(
              metadata: .unparameterized,
              makeOperation: { try await resolved.makeOperation(nil) }
            )
          )
        ]
      }
      guard !dimension.sizes.isEmpty else {
        return [
          .action(
            .planningFailure(
              .invalidDimension(
                benchmarkName: resolved.caseName, reason: "requires at least one size")))
        ]
      }
      if let invalid = dimension.sizes.first(where: { $0.rawValue <= 0 }) {
        return [
          .action(
            .planningFailure(
              .invalidDimension(
                benchmarkName: resolved.caseName,
                reason: "has invalid size \(invalid.rawValue)"
              )
            ))
        ]
      }
      return dimension.sizes.map { size in
        .measure(
          BenchmarkCaseRow(
            metadata: Benchmark.ArgumentRow(
              id: "scale-\(size.rawValue)",
              arguments: [Benchmark.ArgumentValue(label: String(size.rawValue), scale: size)],
              scale: size
            ),
            makeOperation: { try await resolved.makeOperation(size) }
          )
        )
      }
    }
  }
}

private struct PlannedAction: Sendable {
  var action: BenchmarkRunner.Plan.Action
  var caseRow: BenchmarkCaseRow?

  static func measure(_ row: BenchmarkCaseRow) -> PlannedAction {
    PlannedAction(action: .measure(row.metadata), caseRow: row)
  }

  static func action(_ action: BenchmarkRunner.Plan.Action) -> PlannedAction {
    PlannedAction(action: action, caseRow: nil)
  }
}

private struct EffectiveSuiteTraits {
  var configuration: BenchmarkConfiguration?
  var skipReason: String?
  var tags: [String]

  init(suite: BenchmarkSuite) {
    var configurations: [BenchmarkConfiguration] = []
    var skipReason: String?
    var tags: [String] = []
    for trait in suite.traits where trait.benchmarkScoping == .recursive {
      if let configuration = trait.benchmarkConfiguration {
        configurations.append(configuration)
      }
      if skipReason == nil, let reason = trait.benchmarkSkipReason {
        skipReason = reason
      }
      tags.append(contentsOf: trait.benchmarkTags)
    }
    self.configuration = configurations.last
    self.skipReason = skipReason
    self.tags = tags.deduplicated()
  }
}

private struct ResolvedCase {
  var caseName: String
  var configuration: BenchmarkConfiguration
  var dimension: Benchmark.Dimension?
  var parameterizedRows: [BenchmarkCaseRow]?
  var skipReason: String?
  var tags: [String]
  var issue: BenchmarkPlanningIssue?
  var makeOperation: @Sendable (Benchmark.Scale?) async throws -> BenchmarkWorkload

  init(
    suite: BenchmarkSuite,
    suiteTraits: EffectiveSuiteTraits,
    benchmarkCase: BenchmarkCase
  ) {
    caseName = benchmarkCase.name
    parameterizedRows = benchmarkCase.parameterizedRows
    makeOperation = benchmarkCase.makeOperation
    var configurationIssue = false
    var dimensionIssue = false
    var caseConfigurations: [BenchmarkConfiguration] = []
    var caseDimensions: [Benchmark.Dimension] = []
    var caseSkipReason: String?
    var tags = suiteTraits.tags

    for trait in benchmarkCase.traits {
      if let configuration = trait.benchmarkConfiguration {
        caseConfigurations.append(configuration)
      }
      if let dimension = trait.benchmarkDimension {
        caseDimensions.append(dimension)
      }
      if caseSkipReason == nil, let reason = trait.benchmarkSkipReason {
        caseSkipReason = reason
      }
      tags.append(contentsOf: trait.benchmarkTags)
    }

    if caseConfigurations.containsConflict {
      configurationIssue = true
    }
    if let directConfiguration = benchmarkCase.configuration,
      let traitConfiguration = caseConfigurations.last,
      directConfiguration != traitConfiguration
    {
      configurationIssue = true
    }

    if caseDimensions.containsConflict {
      dimensionIssue = true
    }
    if benchmarkCase.parameterizedRows != nil, !caseDimensions.isEmpty {
      dimensionIssue = true
    }
    if let directDimension = benchmarkCase.dimension,
      let traitDimension = caseDimensions.last,
      directDimension != traitDimension
    {
      dimensionIssue = true
    }

    configuration =
      benchmarkCase.configuration
      ?? caseConfigurations.last
      ?? suiteTraits.configuration
      ?? suite.configuration
    dimension = benchmarkCase.dimension ?? caseDimensions.last
    skipReason = caseSkipReason ?? suiteTraits.skipReason
    self.tags = tags.deduplicated()

    if configurationIssue {
      issue = .conflictingConfiguration(benchmarkName: benchmarkCase.name)
    } else if dimensionIssue {
      issue = .conflictingDimension(benchmarkName: benchmarkCase.name)
    } else {
      issue = nil
    }
  }
}

extension Array where Element == String {
  fileprivate func deduplicated() -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for item in self where !seen.contains(item) {
      seen.insert(item)
      result.append(item)
    }
    return result
  }
}

extension Array where Element: Equatable {
  fileprivate var containsConflict: Bool {
    guard let first else {
      return false
    }
    return contains { $0 != first }
  }
}
