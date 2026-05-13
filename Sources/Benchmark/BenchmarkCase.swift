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
  let makeOperation:
    @Sendable (Benchmark.Dimension.Size?) async throws -> @Sendable () async throws -> Void

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
    makeOperation: @escaping @Sendable (Benchmark.Dimension.Size?) async throws ->
      @Sendable () async throws -> Void
  ) {
    self.name = name
    self.configuration = configuration
    self.sourceLocation = sourceLocation ?? BenchmarkSourceLocation(
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )
    self.traits = traits
    self.dimension = dimension
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
    input: @escaping @Sendable (Benchmark.Dimension.Size) -> Input,
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
