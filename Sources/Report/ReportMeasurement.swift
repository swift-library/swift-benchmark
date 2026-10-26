// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

public enum Report {}

extension Report {
  /// A summary statistic over one metric's sample values.
  public enum Statistic: String, Sendable, Codable, CaseIterable {
    /// The smallest value.
    case min
    /// The largest value.
    case max
    /// The arithmetic mean.
    case mean
    /// The 50th percentile.
    case median
    /// The population standard deviation: the square root of the mean
    /// squared distance from the mean.
    case standardDeviation
    /// The 90th percentile.
    case p90
    /// The 95th percentile.
    case p95
    /// The 99th percentile.
    case p99

    /// Reads this statistic from `statistics`.
    public func value(from statistics: Statistics) -> Double {
      switch self {
      case .min:
        return statistics.min
      case .max:
        return statistics.max
      case .mean:
        return statistics.mean
      case .median:
        return statistics.median
      case .standardDeviation:
        return statistics.standardDeviation
      case .p90:
        return statistics.p90
      case .p95:
        return statistics.p95
      case .p99:
        return statistics.p99
      }
    }
  }

  /// Summary statistics of one metric's sample values, in the metric's unit.
  ///
  /// A percentile interpolates linearly between the two sorted values nearest
  /// to position `p × (count − 1)`, and the standard deviation is the
  /// population standard deviation.
  public struct Statistics: Sendable, Equatable, Codable {
    /// The number of values.
    public var count: Int
    /// The smallest value.
    public var min: Double
    /// The largest value.
    public var max: Double
    /// The arithmetic mean.
    public var mean: Double
    /// The 50th percentile.
    public var median: Double
    /// The population standard deviation.
    public var standardDeviation: Double
    /// The 90th percentile.
    public var p90: Double
    /// The 95th percentile.
    public var p95: Double
    /// The 99th percentile.
    public var p99: Double

    /// Creates statistics from values computed elsewhere.
    public init(
      count: Int,
      min: Double,
      max: Double,
      mean: Double,
      median: Double,
      standardDeviation: Double,
      p90: Double,
      p95: Double,
      p99: Double
    ) {
      self.count = count
      self.min = min
      self.max = max
      self.mean = mean
      self.median = median
      self.standardDeviation = standardDeviation
      self.p90 = p90
      self.p95 = p95
      self.p99 = p99
    }

    /// Computes the statistics of `values`. Every statistic is zero when
    /// `values` is empty.
    public init(values: [Double]) {
      let values = values.sorted()
      self.count = values.count

      guard !values.isEmpty else {
        self.min = 0
        self.max = 0
        self.mean = 0
        self.median = 0
        self.standardDeviation = 0
        self.p90 = 0
        self.p95 = 0
        self.p99 = 0
        return
      }

      self.min = values[0]
      self.max = values[values.count - 1]
      let meanValue = values.reduce(0, +) / Double(values.count)
      self.mean = meanValue
      self.median = Self.percentile(0.5, values: values)
      let variance =
        values.reduce(0) { partial, value in
          let delta = value - meanValue
          return partial + delta * delta
        } / Double(values.count)
      self.standardDeviation = variance.squareRoot()
      self.p90 = Self.percentile(0.90, values: values)
      self.p95 = Self.percentile(0.95, values: values)
      self.p99 = Self.percentile(0.99, values: values)
    }

    /// The statistics divided by `size`, for per-unit comparisons across
    /// Dimension sizes.
    public func amortized(by size: Benchmark.Scale) -> Statistics {
      let divisor = Double(size.rawValue)
      guard divisor != 0 else {
        return self
      }
      return Statistics(
        count: count,
        min: min / divisor,
        max: max / divisor,
        mean: mean / divisor,
        median: median / divisor,
        standardDeviation: standardDeviation / divisor,
        p90: p90 / divisor,
        p95: p95 / divisor,
        p99: p99 / divisor
      )
    }

    private static func percentile(_ percentile: Double, values: [Double]) -> Double {
      guard values.count > 1 else {
        return values.first ?? 0
      }

      let clamped = Swift.min(Swift.max(percentile, 0), 1)
      let position = clamped * Double(values.count - 1)
      let lower = Int(position.rounded(.down))
      let upper = Int(position.rounded(.up))
      guard lower != upper else {
        return values[lower]
      }

      let fraction = position - Double(lower)
      return values[lower] + (values[upper] - values[lower]) * fraction
    }
  }

  /// The samples of one benchmark case, grouped into Dimension or argument rows.
  public struct Measurement: Sendable, Equatable, Codable {
    /// One row per Dimension size or argument row, or a single row for an
    /// unparameterized case.
    public var rows: [Row]

    /// Creates a measurement from its rows.
    public init(rows: [Row]) {
      self.rows = rows
    }

    /// Creates a measurement with one row and no Dimension size.
    public init(samples: [SampleReport], metrics: [Benchmark.Metric]) {
      self.init(rows: [Row(size: nil, samples: samples, metrics: metrics)])
    }

    /// Every row's samples, timed and counting alike.
    public var samples: [SampleReport] {
      rows.flatMap(\.samples)
    }

    /// The metrics that have values in any row, ordered by name.
    public var metrics: [Benchmark.Metric] {
      Report.mergedMetrics(rows.map(\.metrics))
    }

    /// Statistics of `metric` over the samples of every row, or `nil` when no
    /// sample has a value for it.
    public func statistics(for metric: Benchmark.Metric) -> Statistics? {
      let values = samples.compactMap { $0.value(for: metric) }
      return values.isEmpty ? nil : Statistics(values: values)
    }
  }

  static func mergedMetrics(_ groups: [[Benchmark.Metric]]) -> [Benchmark.Metric] {
    var byName: [String: Benchmark.Metric] = [:]
    for metric in groups.joined() where byName[metric.name] == nil {
      byName[metric.name] = metric
    }
    return byName.values.sorted { $0.name < $1.name }
  }
}

extension Report.Measurement {
  /// The samples of one Dimension size or argument row, with their statistics.
  public struct Row: Sendable, Equatable, Codable {
    /// The row's identifier: its values' descriptions for an argument row,
    /// `scale-<size>` for a Dimension size, and `nil` for an unparameterized
    /// case.
    public var id: String?
    /// The row's Dimension size, if it has one.
    public var size: Benchmark.Scale?
    /// The values of an argument row's arguments.
    public var arguments: [Benchmark.ArgumentValue]
    /// The metrics measured for this row, ordered by name.
    public var metrics: [Benchmark.Metric]
    /// The row's samples, timed and counting alike.
    public var samples: [SampleReport]
    /// Statistics keyed by metric name.
    public var statistics: [String: Report.Statistics]
    /// Statistics per unit of ``size``, keyed by metric name; `nil` without a size.
    public var amortized: [String: Report.Statistics]?

    /// Creates a row and computes its statistics, and its amortized
    /// statistics when it has a size.
    public init(
      id: String? = nil,
      size: Benchmark.Scale?,
      arguments: [Benchmark.ArgumentValue] = [],
      samples: [SampleReport],
      metrics: [Benchmark.Metric]
    ) {
      let metrics = Report.mergedMetrics([metrics])
      var statistics: [String: Report.Statistics] = [:]
      for metric in metrics {
        let values = samples.compactMap { $0.value(for: metric) }
        if !values.isEmpty {
          statistics[metric.name] = Report.Statistics(values: values)
        }
      }
      self.id = id
      self.size = size
      self.arguments = arguments
      self.metrics = metrics
      self.samples = samples
      self.statistics = statistics
      self.amortized = size.map { size in statistics.mapValues { $0.amortized(by: size) } }
    }

    /// The row's statistics for `metric`, or `nil` when no sample measured it.
    public func statistics(for metric: Benchmark.Metric) -> Report.Statistics? {
      statistics[metric.name]
    }

    private enum CodingKeys: String, CodingKey {
      case id
      case size
      case arguments
      case metrics
      case samples
      case statistics
      case amortized
    }

    /// Decodes a row. Statistics are recomputed from the samples, so a decoded
    /// row always matches its samples.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        id: try container.decodeIfPresent(String.self, forKey: .id),
        size: try container.decodeIfPresent(Benchmark.Scale.self, forKey: .size),
        arguments: try container.decodeIfPresent(
          [Benchmark.ArgumentValue].self, forKey: .arguments) ?? [],
        samples: try container.decode([SampleReport].self, forKey: .samples),
        metrics: try container.decode([Benchmark.Metric].self, forKey: .metrics)
      )
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeIfPresent(id, forKey: .id)
      try container.encodeIfPresent(size, forKey: .size)
      try container.encode(arguments, forKey: .arguments)
      try container.encode(metrics, forKey: .metrics)
      try container.encode(samples, forKey: .samples)
      try container.encode(statistics, forKey: .statistics)
      try container.encodeIfPresent(amortized, forKey: .amortized)
    }
  }
}
