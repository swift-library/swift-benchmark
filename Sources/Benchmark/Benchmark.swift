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
    input: @escaping @Sendable (Benchmark.Dimension.Size) async throws -> Input,
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
    input: @escaping @Sendable (Benchmark.Dimension.Size) -> Input,
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
