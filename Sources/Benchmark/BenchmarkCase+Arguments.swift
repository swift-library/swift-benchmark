// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

extension BenchmarkCase {
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
