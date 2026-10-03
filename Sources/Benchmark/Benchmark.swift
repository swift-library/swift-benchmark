// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct Benchmark: Sendable {
  public let benchmarkCase: BenchmarkCase

  public init(_ benchmarkCase: BenchmarkCase) {
    self.benchmarkCase = benchmarkCase
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
    self.init(
      BenchmarkCase(
        name,
        arguments: arguments,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
    self.init(
      BenchmarkCase(
        name,
        arguments: collection1,
        collection2,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
    self.init(
      BenchmarkCase(
        name,
        arguments: zipped,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        operation
      )
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
      BenchmarkCase(
        name,
        dimension: dimension,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        input: input,
        operation
      )
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
      BenchmarkCase(
        name,
        dimension: dimension,
        configuration: configuration,
        traits: traits,
        sourceLocation: sourceLocation,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column,
        input: input,
        operation
      )
    )
  }
}
