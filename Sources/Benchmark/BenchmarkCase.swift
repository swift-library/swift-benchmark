// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

public struct BenchmarkSourceLocation: Sendable, Equatable, Codable {
  public var fileID: String
  public var filePath: String
  public var line: Int
  public var column: Int

  public init(fileID: String, filePath: String, line: Int, column: Int) {
    self.fileID = fileID
    self.filePath = filePath
    self.line = line
    self.column = column
  }
}

public struct BenchmarkCase: Sendable {
  public let name: String
  public let configuration: BenchmarkConfiguration?
  public let sourceLocation: BenchmarkSourceLocation
  public let traits: [any BenchmarkCaseTrait]
  public let dimension: Benchmark.Dimension?
  let parameterizedRows: [BenchmarkCaseRow]?
  let makeOperation: @Sendable (Benchmark.Scale?) async throws -> @Sendable () async throws -> Void

  private init(
    _ name: String,
    configuration: BenchmarkConfiguration?,
    sourceLocation: BenchmarkSourceLocation?,
    fileID: String,
    filePath: String,
    line: Int,
    column: Int,
    traits: [any BenchmarkCaseTrait],
    dimension: Benchmark.Dimension?,
    parameterizedRows: [BenchmarkCaseRow]? = nil,
    makeOperation:
      @escaping @Sendable (Benchmark.Scale?) async throws ->
      @Sendable () async throws -> Void
  ) {
    self.name = name
    self.configuration = configuration
    self.sourceLocation =
      sourceLocation
      ?? BenchmarkSourceLocation(
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    self.traits = traits
    self.dimension = dimension
    self.parameterizedRows = parameterizedRows
    self.makeOperation = makeOperation
  }

  public init(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () async throws -> Void
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in operation }
    )
  }

  public init(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () throws -> Void
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in { try operation() } }
    )
  }

  public init(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () -> Void
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in { operation() } }
    )
  }

  public init<T: Sendable>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () async throws -> T
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in
        {
          blackHole(try await operation())
        }
      }
    )
  }

  public init<T: Sendable>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () async -> T
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in
        {
          blackHole(await operation())
        }
      }
    )
  }

  public init<T: Sendable>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () throws -> T
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in
        {
          blackHole(try operation())
        }
      }
    )
  }

  public init<T: Sendable>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable () -> T
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      makeOperation: { _ in
        {
          blackHole(operation())
        }
      }
    )
  }

  public init<C: Collection>(
    _ name: String,
    arguments: C,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable (C.Element) async throws -> Void
  ) where C.Element: Sendable {
    let values = Array(arguments)
    let rows = values.enumerated().map { index, value in
      BenchmarkCaseRow(
        metadata: Benchmark.ArgumentRow(
          id: Self.argumentRowID(index: index, values: [value as Any]),
          arguments: [Benchmark.ArgumentValue(value)]
        ),
        makeOperation: {
          {
            try await operation(value)
          }
        }
      )
    }
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      parameterizedRows: rows,
      makeOperation: { _ in
        throw BenchmarkRunnerError.invalidConfiguration(
          "Parameterized benchmark '\(name)' requires an argument row."
        )
      }
    )
  }

  public init<C1: Collection, C2: Collection>(
    _ name: String,
    arguments collection1: C1,
    _ collection2: C2,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable (C1.Element, C2.Element) async throws -> Void
  ) where C1.Element: Sendable, C2.Element: Sendable {
    let values1 = Array(collection1)
    let values2 = Array(collection2)
    var rows: [BenchmarkCaseRow] = []
    var index = 0
    for value1 in values1 {
      for value2 in values2 {
        rows.append(
          BenchmarkCaseRow(
            metadata: Benchmark.ArgumentRow(
              id: Self.argumentRowID(index: index, values: [value1 as Any, value2 as Any]),
              arguments: [
                Benchmark.ArgumentValue(value1),
                Benchmark.ArgumentValue(value2),
              ]
            ),
            makeOperation: {
              {
                try await operation(value1, value2)
              }
            }
          )
        )
        index += 1
      }
    }
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      parameterizedRows: rows,
      makeOperation: { _ in
        throw BenchmarkRunnerError.invalidConfiguration(
          "Parameterized benchmark '\(name)' requires an argument row."
        )
      }
    )
  }

  public init<C1: Sequence, C2: Sequence>(
    _ name: String,
    arguments zipped: Zip2Sequence<C1, C2>,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    _ operation: @escaping @Sendable (C1.Element, C2.Element) async throws -> Void
  ) where C1.Element: Sendable, C2.Element: Sendable {
    let pairs = Array(zipped)
    let rows = pairs.enumerated().map { index, pair in
      BenchmarkCaseRow(
        metadata: Benchmark.ArgumentRow(
          id: Self.argumentRowID(index: index, values: [pair.0 as Any, pair.1 as Any]),
          arguments: [
            Benchmark.ArgumentValue(pair.0),
            Benchmark.ArgumentValue(pair.1),
          ]
        ),
        makeOperation: {
          {
            try await operation(pair.0, pair.1)
          }
        }
      )
    }
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: nil,
      parameterizedRows: rows,
      makeOperation: { _ in
        throw BenchmarkRunnerError.invalidConfiguration(
          "Parameterized benchmark '\(name)' requires an argument row."
        )
      }
    )
  }

  public init<Input: Sendable>(
    _ name: String,
    dimension: Benchmark.Dimension,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    input: @escaping @Sendable (Benchmark.Scale) async throws -> Input,
    _ operation: @escaping @Sendable (Input) async throws -> Void
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: dimension,
      makeOperation: { size in
        guard let size else {
          throw BenchmarkRunnerError.invalidConfiguration(
            "Dimension benchmark '\(name)' requires a Dimension size."
          )
        }
        let value = try await input(size)
        return {
          try await operation(value)
        }
      }
    )
  }

  public init<Input: Sendable>(
    _ name: String,
    dimension: Benchmark.Dimension,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    input: @escaping @Sendable (Benchmark.Scale) -> Input,
    _ operation: @escaping @Sendable (Input) throws -> Void
  ) {
    self.init(
      name,
      configuration: configuration,
      sourceLocation: sourceLocation,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column,
      traits: traits,
      dimension: dimension,
      makeOperation: { size in
        guard let size else {
          throw BenchmarkRunnerError.invalidConfiguration(
            "Dimension benchmark '\(name)' requires a Dimension size."
          )
        }
        let value = input(size)
        return {
          try operation(value)
        }
      }
    )
  }
}

extension BenchmarkCase {
  fileprivate static func argumentRowID(index: Int, values: [Any]) -> String {
    let labels = values.map { stableIDComponent(String(describing: $0)) }
      .filter { !$0.isEmpty }
      .joined(separator: "-")
    let suffix = labels.isEmpty ? "arguments" : labels
    return "arguments-\(index)-\(suffix)"
  }

  fileprivate static func stableIDComponent(_ value: String) -> String {
    let normalized =
      value
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
    return normalized
  }
}
