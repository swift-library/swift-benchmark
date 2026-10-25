// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// One measurement of a benchmark case.
///
/// A sample measures `batchSize` consecutive calls of the workload and stores
/// each metric's value per single call.
public struct Sample: Sendable, Equatable {
  public let iteration: Int
  /// The number of consecutive calls the sample measured.
  public let batchSize: Int
  /// Each metric's value per call.
  public let values: [Benchmark.Metric: Double]

  /// Creates a sample from per-call values.
  public init(iteration: Int, batchSize: Int = 1, values: [Benchmark.Metric: Double]) {
    self.iteration = iteration
    self.batchSize = batchSize
    self.values = values
  }

  /// The per-call value of `metric`, or `nil` when the sample did not measure it.
  public func value(for metric: Benchmark.Metric) -> Double? {
    values[metric]
  }
}
