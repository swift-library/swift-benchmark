// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkExecutionContext: Sendable, Equatable {
  public var suiteName: String
  public var caseName: String
  public var size: Benchmark.Scale?
  public var arguments: [Benchmark.ArgumentValue]
  public var phase: BenchmarkPhase

  public init(
    suiteName: String,
    caseName: String,
    size: Benchmark.Scale? = nil,
    arguments: [Benchmark.ArgumentValue] = [],
    phase: BenchmarkPhase
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.size = size
    self.arguments = arguments
    self.phase = phase
  }
}

public protocol BenchmarkExecutionObserver: Sendable {
  func benchmarkWillRun(context: BenchmarkExecutionContext) async
  func benchmarkDidRun(context: BenchmarkExecutionContext, durationNanoseconds: UInt64?) async
  func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async
}

extension BenchmarkExecutionObserver {
  public func benchmarkWillRun(context: BenchmarkExecutionContext) async {}
  public func benchmarkDidRun(context: BenchmarkExecutionContext, durationNanoseconds: UInt64?)
    async
  {}
  public func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async {}
}
