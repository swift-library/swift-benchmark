// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// One measurement of a benchmark case.
///
/// A sample measures `batchSize` consecutive calls of the workload and stores
/// each metric's value per single call.
public struct Sample: Sendable, Equatable {
  public let iteration: Int
  public let batchSize: Int
  public let values: [Benchmark.Metric: Double]

  public init(iteration: Int, batchSize: Int = 1, values: [Benchmark.Metric: Double]) {
    self.iteration = iteration
    self.batchSize = batchSize
    self.values = values
  }

  public func value(for metric: Benchmark.Metric) -> Double? {
    values[metric]
  }
}
