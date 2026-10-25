// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Synchronization

/// Accumulates the values a workload records with ``Benchmark/record(_:for:)``
/// during one sample.
final class CustomMetricRecorder: Sendable {
  @TaskLocal static var current: CustomMetricRecorder?

  private let totals = Mutex<[Benchmark.Metric: Double]>([:])

  func add(_ value: Double, for metric: Benchmark.Metric) {
    guard !Benchmark.Metric.builtIn.contains(metric) else {
      return
    }
    totals.withLock { $0[metric, default: 0] += value }
  }

  func values() -> [Benchmark.Metric: Double] {
    totals.withLock { $0 }
  }
}

extension Benchmark {
  /// Adds `value` to `metric` for the sample being measured.
  ///
  /// Values recorded during one sample are summed and divided by the sample's
  /// batch size, like the built-in metrics. The call does nothing outside a
  /// measured sample and for the names of ``Metric/builtIn`` metrics, which
  /// the runner measures itself.
  public static func record(_ value: Double, for metric: Metric) {
    CustomMetricRecorder.current?.add(value, for: metric)
  }
}
