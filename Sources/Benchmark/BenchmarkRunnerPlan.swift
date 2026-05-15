import Foundation

public extension BenchmarkRunner {
  struct Plan: Sendable {
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
          let resolved = ResolvedCase(suite: suite, suiteTraits: suiteTraits, benchmarkCase: benchmarkCase)
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
          return [.action(.planningFailure(.invalidArguments(benchmarkName: resolved.caseName, reason: "requires at least one argument")))]
        }
        if let invalid = rows.first(where: { ($0.metadata.scale?.rawValue ?? 1) <= 0 }) {
          return [
            .action(.planningFailure(
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
        return [.action(.planningFailure(.invalidDimension(benchmarkName: resolved.caseName, reason: "requires at least one size")))]
      }
      if let invalid = dimension.sizes.first(where: { $0.rawValue <= 0 }) {
        return [
          .action(.planningFailure(
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

public extension BenchmarkRunner.Plan {
  struct Filter: Sendable, Equatable {
    public var suiteName: String?
    public var caseName: String?
    public var suitePattern: String?
    public var casePattern: String?
    public var tags: [String]

    public init(
      suiteName: String? = nil,
      caseName: String? = nil,
      suitePattern: String? = nil,
      casePattern: String? = nil,
      tags: [String] = []
    ) {
      self.suiteName = suiteName
      self.caseName = caseName
      self.suitePattern = suitePattern
      self.casePattern = casePattern
      self.tags = tags
    }

    public static var all: Filter {
      Filter()
    }

    public func matchesSuite(_ name: String) -> Bool {
      matches(name: name, exact: suiteName, pattern: suitePattern)
    }

    public func matchesCase(_ name: String) -> Bool {
      matches(name: name, exact: caseName, pattern: casePattern)
    }

    public func matchesTags(_ candidateTags: [String]) -> Bool {
      tags.allSatisfy { candidateTags.contains($0) }
    }

    private func matches(name: String, exact: String?, pattern: String?) -> Bool {
      if let exact, exact != name {
        return false
      }
      if let pattern, !Self.matchesPattern(pattern, name: name) {
        return false
      }
      return true
    }

    private static func matchesPattern(_ pattern: String, name: String) -> Bool {
      guard pattern.contains("*") else {
        return name.contains(pattern)
      }
      let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
      var remainder = name[...]
      for (index, part) in parts.enumerated() where !part.isEmpty {
        guard let range = remainder.range(of: part) else {
          return false
        }
        if index == 0, !pattern.hasPrefix("*"), range.lowerBound != remainder.startIndex {
          return false
        }
        remainder = remainder[range.upperBound...]
      }
      if let last = parts.last, !last.isEmpty, !pattern.hasSuffix("*") {
        return name.hasSuffix(last)
      }
      return true
    }
  }

  struct Step: Sendable {
    public var suite: BenchmarkSuite
    public var benchmarkCase: BenchmarkCase
    public var configuration: BenchmarkConfiguration
    public var tags: [String]
    public var action: Action
    var caseRow: BenchmarkCaseRow?

    public var id: String {
      [
        "benchmark",
        stableIDComponent(suiteName),
        stableIDComponent(caseName),
        rowID,
      ]
      .compactMap { $0 }
      .joined(separator: ":")
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

    private func stableIDComponent(_ value: String) -> String {
      let normalized = value
        .lowercased()
        .map { character in
          character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { partial, character in
          if character == "-", partial.last == "-" {
            return
          }
          partial.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      return normalized.isEmpty ? "unnamed" : normalized
    }
  }

  enum Action: Sendable {
    case measure(Benchmark.ArgumentRow)
    case skip(reason: String)
    case planningFailure(BenchmarkPlanningIssue)
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
  var makeOperation: @Sendable (Benchmark.Scale?) async throws -> @Sendable () async throws -> Void

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

    configuration = benchmarkCase.configuration
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

private extension Array where Element == String {
  func deduplicated() -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for item in self where !seen.contains(item) {
      seen.insert(item)
      result.append(item)
    }
    return result
  }
}

private extension Array where Element: Equatable {
  var containsConflict: Bool {
    guard let first else {
      return false
    }
    return contains { $0 != first }
  }
}
