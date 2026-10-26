// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkExecutionContext: Sendable, Equatable {
  public var suiteName: String
  public var caseName: String
  public var size: Benchmark.Scale?
  public var arguments: [Benchmark.ArgumentValue]
  /// The identifier of the step's argument row or Dimension size, or `nil`
  /// for an unparameterized case.
  public var rowID: String?
  public var phase: BenchmarkPhase

  public init(
    suiteName: String,
    caseName: String,
    size: Benchmark.Scale? = nil,
    arguments: [Benchmark.ArgumentValue] = [],
    rowID: String? = nil,
    phase: BenchmarkPhase
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.size = size
    self.arguments = arguments
    self.rowID = rowID
    self.phase = phase
  }
}

public protocol BenchmarkExecutionObserver: Sendable {
  func benchmarkWillRun(context: BenchmarkExecutionContext) async
  /// Called after a warmup call or a measured sample. `sample` is `nil` for warmup.
  func benchmarkDidRun(context: BenchmarkExecutionContext, sample: Sample?) async
  func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async
}

extension BenchmarkExecutionObserver {
  public func benchmarkWillRun(context: BenchmarkExecutionContext) async {}
  public func benchmarkDidRun(context: BenchmarkExecutionContext, sample: Sample?) async {}
  public func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async {}
}
