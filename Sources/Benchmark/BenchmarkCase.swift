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

  init(
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

}
