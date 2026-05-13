public struct BenchmarkExecutionContext: Sendable, Equatable {
  public var suiteName: String
  public var caseName: String
  public var size: Benchmark.Dimension.Size?
  public var phase: BenchmarkPhase

  public init(
    suiteName: String,
    caseName: String,
    size: Benchmark.Dimension.Size? = nil,
    phase: BenchmarkPhase
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.size = size
    self.phase = phase
  }
}

public protocol BenchmarkExecutionObserver: Sendable {
  func benchmarkWillRun(context: BenchmarkExecutionContext) async
  func benchmarkDidRun(context: BenchmarkExecutionContext, durationNanoseconds: UInt64?) async
  func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async
}

public extension BenchmarkExecutionObserver {
  func benchmarkWillRun(context: BenchmarkExecutionContext) async {}
  func benchmarkDidRun(context: BenchmarkExecutionContext, durationNanoseconds: UInt64?) async {}
  func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async {}
}
