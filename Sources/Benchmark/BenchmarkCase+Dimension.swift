// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension BenchmarkCase {
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
