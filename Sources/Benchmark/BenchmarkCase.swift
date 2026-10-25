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
  let makeOperation: @Sendable (Benchmark.Scale?) async throws -> BenchmarkWorkload

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
    makeOperation: @escaping @Sendable (Benchmark.Scale?) async throws -> BenchmarkWorkload
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
      makeOperation: { _ in .asynchronous(operation) }
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
      makeOperation: { _ in .synchronous(operation) }
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
      makeOperation: { _ in .synchronous(operation) }
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
      makeOperation: { _ in .asynchronous { blackHole(try await operation()) } }
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
      makeOperation: { _ in .asynchronous { blackHole(await operation()) } }
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
      makeOperation: { _ in .synchronous { blackHole(try operation()) } }
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
      makeOperation: { _ in .synchronous { blackHole(operation()) } }
    )
  }

  /// Creates a benchmark with one argument row per element of `arguments`.
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
    self.init(
      name, configuration: configuration, sourceLocation: sourceLocation, fileID: fileID,
      filePath: filePath, line: line, column: column, traits: traits,
      rows: Self.rows(arguments.map { value in [value] }) { values in
        let value = values[0] as! C.Element
        return .asynchronous { try await operation(value) }
      }
    )
  }

  /// Creates a benchmark with one argument row per element of `arguments`.
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
    _ operation: @escaping @Sendable (C.Element) throws -> Void
  ) where C.Element: Sendable {
    self.init(
      name, configuration: configuration, sourceLocation: sourceLocation, fileID: fileID,
      filePath: filePath, line: line, column: column, traits: traits,
      rows: Self.rows(arguments.map { value in [value] }) { values in
        let value = values[0] as! C.Element
        return .synchronous { try operation(value) }
      }
    )
  }

  /// Creates a benchmark with one argument row per pair of elements, varying
  /// the second collection fastest.
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
    self.init(
      name, configuration: configuration, sourceLocation: sourceLocation, fileID: fileID,
      filePath: filePath, line: line, column: column, traits: traits,
      rows: Self.rows(Self.product(collection1, collection2)) { values in
        let (value1, value2) = (values[0] as! C1.Element, values[1] as! C2.Element)
        return .asynchronous { try await operation(value1, value2) }
      }
    )
  }

  /// Creates a benchmark with one argument row per pair of elements, varying
  /// the second collection fastest.
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
    _ operation: @escaping @Sendable (C1.Element, C2.Element) throws -> Void
  ) where C1.Element: Sendable, C2.Element: Sendable {
    self.init(
      name, configuration: configuration, sourceLocation: sourceLocation, fileID: fileID,
      filePath: filePath, line: line, column: column, traits: traits,
      rows: Self.rows(Self.product(collection1, collection2)) { values in
        let (value1, value2) = (values[0] as! C1.Element, values[1] as! C2.Element)
        return .synchronous { try operation(value1, value2) }
      }
    )
  }

  /// Creates a benchmark with one argument row per pair of zipped elements.
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
    self.init(
      name, configuration: configuration, sourceLocation: sourceLocation, fileID: fileID,
      filePath: filePath, line: line, column: column, traits: traits,
      rows: Self.rows(zipped.map { pair in [pair.0, pair.1] }) { values in
        let (value1, value2) = (values[0] as! C1.Element, values[1] as! C2.Element)
        return .asynchronous { try await operation(value1, value2) }
      }
    )
  }

  /// Creates a benchmark with one argument row per pair of zipped elements.
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
    _ operation: @escaping @Sendable (C1.Element, C2.Element) throws -> Void
  ) where C1.Element: Sendable, C2.Element: Sendable {
    self.init(
      name, configuration: configuration, sourceLocation: sourceLocation, fileID: fileID,
      filePath: filePath, line: line, column: column, traits: traits,
      rows: Self.rows(zipped.map { pair in [pair.0, pair.1] }) { values in
        let (value1, value2) = (values[0] as! C1.Element, values[1] as! C2.Element)
        return .synchronous { try operation(value1, value2) }
      }
    )
  }

  private init(
    _ name: String,
    configuration: BenchmarkConfiguration?,
    sourceLocation: BenchmarkSourceLocation?,
    fileID: String,
    filePath: String,
    line: Int,
    column: Int,
    traits: [any BenchmarkCaseTrait],
    rows: [BenchmarkCaseRow]
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
        return .asynchronous { try await operation(value) }
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
        return .synchronous { try operation(value) }
      }
    )
  }
}

extension BenchmarkCase {
  /// Builds one argument row per element of `argumentLists`, in order.
  fileprivate static func rows(
    _ argumentLists: [[any Sendable]],
    workload: @escaping @Sendable ([any Sendable]) -> BenchmarkWorkload
  ) -> [BenchmarkCaseRow] {
    argumentLists.enumerated().map { index, values in
      BenchmarkCaseRow(
        metadata: Benchmark.ArgumentRow(
          id: argumentRowID(index: index, values: values.map { $0 as Any }),
          arguments: values.map { Benchmark.ArgumentValue($0) }
        ),
        makeOperation: { workload(values) }
      )
    }
  }

  /// Every pair of an element of `collection1` with an element of
  /// `collection2`, varying the second element fastest.
  fileprivate static func product<C1: Collection, C2: Collection>(
    _ collection1: C1,
    _ collection2: C2
  ) -> [[any Sendable]] where C1.Element: Sendable, C2.Element: Sendable {
    collection1.flatMap { value1 in collection2.map { value2 in [value1, value2] } }
  }

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
