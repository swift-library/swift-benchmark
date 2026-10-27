// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

// Cases whose every call takes a fresh input from `setup`, such as a shuffled
// array for a sort. The runner makes a batch's inputs before measuring the
// batch and releases them after it, so neither `setup` nor freeing the inputs
// is timed or counted. `operation` receives each input `inout` and may change
// it; the input is discarded after the call.

extension BenchmarkCase {
  /// Creates a case whose every call takes a fresh input from `setup`.
  public init<Input>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable () throws -> Input,
    _ operation: @escaping @Sendable (inout Input) throws -> Void
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
        .prepared { count in
          try PreparedBatch.make(count: count, setup: setup, operation: operation)
        }
      }
    )
  }

  /// Creates a case whose every call takes a fresh input from `setup`, with
  /// an asynchronous setup and operation.
  public init<Input>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable () async throws -> Input,
    _ operation: @escaping @Sendable (inout Input) async throws -> Void
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
        .prepared { count in
          try await PreparedBatch.make(count: count, setup: setup, operation: operation)
        }
      }
    )
  }

  /// Creates a Dimension case whose every call takes a fresh input that
  /// `setup` makes for the row's size.
  public init<Input>(
    _ name: String,
    dimension: Benchmark.Dimension,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable (Benchmark.Scale) throws -> Input,
    _ operation: @escaping @Sendable (inout Input) throws -> Void
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
        let size = try Self.requiredSize(size, name: name)
        return .prepared { count in
          try PreparedBatch.make(count: count, setup: { try setup(size) }, operation: operation)
        }
      }
    )
  }

  /// Creates a Dimension case whose every call takes a fresh input that
  /// `setup` makes for the row's size, with an asynchronous setup and
  /// operation.
  public init<Input>(
    _ name: String,
    dimension: Benchmark.Dimension,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable (Benchmark.Scale) async throws -> Input,
    _ operation: @escaping @Sendable (inout Input) async throws -> Void
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
        let size = try Self.requiredSize(size, name: name)
        return .prepared { count in
          try await PreparedBatch.make(
            count: count, setup: { try await setup(size) }, operation: operation)
        }
      }
    )
  }

  private static func requiredSize(_ size: Benchmark.Scale?, name: String) throws
    -> Benchmark.Scale
  {
    guard let size else {
      throw BenchmarkRunnerError.invalidConfiguration(
        "Dimension benchmark '\(name)' requires a Dimension size."
      )
    }
    return size
  }
}

extension Benchmark {
  /// Creates a benchmark whose every call takes a fresh input from `setup`.
  public init<Input>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable () throws -> Input,
    _ operation: @escaping @Sendable (inout Input) throws -> Void
  ) {
    self.init(
      BenchmarkCase(
        name, configuration: configuration, traits: traits, sourceLocation: sourceLocation,
        fileID: fileID, filePath: filePath, line: line, column: column, setup: setup, operation)
    )
  }

  /// Creates a benchmark whose every call takes a fresh input from `setup`,
  /// with an asynchronous setup and operation.
  public init<Input>(
    _ name: String,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable () async throws -> Input,
    _ operation: @escaping @Sendable (inout Input) async throws -> Void
  ) {
    self.init(
      BenchmarkCase(
        name, configuration: configuration, traits: traits, sourceLocation: sourceLocation,
        fileID: fileID, filePath: filePath, line: line, column: column, setup: setup, operation)
    )
  }

  /// Creates a Dimension benchmark whose every call takes a fresh input that
  /// `setup` makes for the row's size.
  public init<Input>(
    _ name: String,
    dimension: Benchmark.Dimension,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable (Benchmark.Scale) throws -> Input,
    _ operation: @escaping @Sendable (inout Input) throws -> Void
  ) {
    self.init(
      BenchmarkCase(
        name, dimension: dimension, configuration: configuration, traits: traits,
        sourceLocation: sourceLocation, fileID: fileID, filePath: filePath, line: line,
        column: column, setup: setup, operation)
    )
  }

  /// Creates a Dimension benchmark whose every call takes a fresh input that
  /// `setup` makes for the row's size, with an asynchronous setup and
  /// operation.
  public init<Input>(
    _ name: String,
    dimension: Benchmark.Dimension,
    configuration: BenchmarkConfiguration? = nil,
    traits: [any BenchmarkCaseTrait] = [],
    sourceLocation: BenchmarkSourceLocation? = nil,
    fileID: String = #fileID,
    filePath: String = #filePath,
    line: Int = #line,
    column: Int = #column,
    setup: @escaping @Sendable (Benchmark.Scale) async throws -> Input,
    _ operation: @escaping @Sendable (inout Input) async throws -> Void
  ) {
    self.init(
      BenchmarkCase(
        name, dimension: dimension, configuration: configuration, traits: traits,
        sourceLocation: sourceLocation, fileID: fileID, filePath: filePath, line: line,
        column: column, setup: setup, operation)
    )
  }
}
