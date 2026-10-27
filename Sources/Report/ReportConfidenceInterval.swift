// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension Report {
  /// A range that holds the difference between a run's statistic and its
  /// baseline's with the stated confidence, in the metric's unit.
  ///
  /// Comparisons estimate it by bootstrap: they resample each side's values
  /// with replacement, take the difference of the resamples' statistics, and
  /// keep the central ``level`` share of those differences. The resampling is
  /// seeded from the compared case, row, metric and statistic, so the same
  /// values always give the same interval.
  public struct ConfidenceInterval: Sendable, Equatable, Codable {
    /// The share of resampled differences inside the interval, such as 0.95.
    public var level: Double
    /// The smallest difference inside the interval.
    public var lowerBound: Double
    /// The largest difference inside the interval.
    public var upperBound: Double

    /// Creates an interval.
    public init(level: Double, lowerBound: Double, upperBound: Double) {
      self.level = level
      self.lowerBound = lowerBound
      self.upperBound = upperBound
    }

    /// Whether the interval leaves out zero, so noise alone is unlikely to
    /// explain the difference.
    public var excludesZero: Bool {
      lowerBound > 0 || upperBound < 0
    }
  }
}

extension Report.ConfidenceInterval {
  /// The confidence level of comparisons.
  static let comparisonLevel = 0.95
  static let resampleCount = 1_000

  /// The bootstrap interval of `statistic(current) - statistic(baseline)`,
  /// or `nil` when either side has fewer than two values.
  static func difference(
    of statistic: Report.Statistic,
    current: [Double],
    baseline: [Double],
    seed: UInt64,
    level: Double = comparisonLevel
  ) -> Report.ConfidenceInterval? {
    guard current.count >= 2, baseline.count >= 2 else {
      return nil
    }
    var generator = SplitMix64(seed: seed)
    var currentResample = current
    var baselineResample = baseline
    var differences: [Double] = []
    differences.reserveCapacity(resampleCount)
    for _ in 0..<resampleCount {
      resample(current, into: &currentResample, using: &generator)
      resample(baseline, into: &baselineResample, using: &generator)
      differences.append(
        statistic.value(of: &currentResample) - statistic.value(of: &baselineResample))
    }
    differences.sort()
    let tail = (1 - level) / 2
    return Report.ConfidenceInterval(
      level: level,
      lowerBound: Report.Statistics.percentile(tail, sortedValues: differences),
      upperBound: Report.Statistics.percentile(1 - tail, sortedValues: differences)
    )
  }

  /// A seed that names one comparison: the same names give the same seed in
  /// every process and on every platform, unlike `Hasher`.
  static func seed(_ names: [String]) -> UInt64 {
    // FNV-1a, with a zero byte between names.
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for name in names {
      for byte in name.utf8 + [0] {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
      }
    }
    return hash
  }

  private static func resample(
    _ values: [Double], into resample: inout [Double], using generator: inout SplitMix64
  ) {
    let count = UInt64(values.count)
    for index in resample.indices {
      resample[index] = values[Int(generator.next().multipliedFullWidth(by: count).high)]
    }
  }
}

/// A small, fast generator whose sequence is fixed by its seed on every
/// platform and Swift version.
struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var value = state
    value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
    value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
    return value ^ (value >> 31)
  }
}

extension Report.Statistic {
  /// This statistic of `values`, computed as ``Report/Statistics`` computes
  /// it. Percentiles sort `values` in place.
  func value(of values: inout [Double]) -> Double {
    switch self {
    case .min:
      return values.min() ?? 0
    case .max:
      return values.max() ?? 0
    case .mean:
      return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    case .standardDeviation:
      guard !values.isEmpty else {
        return 0
      }
      let mean = values.reduce(0, +) / Double(values.count)
      let variance =
        values.reduce(0) { partial, value in
          partial + (value - mean) * (value - mean)
        } / Double(values.count)
      return variance.squareRoot()
    case .median, .p90, .p95, .p99:
      values.sort()
      let percentile: Double =
        switch self {
        case .median: 0.5
        case .p90: 0.90
        case .p95: 0.95
        default: 0.99
        }
      return Report.Statistics.percentile(percentile, sortedValues: values)
    }
  }
}
