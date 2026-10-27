// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

extension Report {
  public struct DimensionCurve: Sendable, Equatable, Codable {
    public var id: ReportID
    public var scope: ReportScope
    /// The metric the curve plots.
    public var metric: Benchmark.Metric
    /// The statistic the curve plots at each size.
    public var statistic: Statistic
    public var points: [Point]
    /// The growth model that best fits the points, or `nil` with fewer than
    /// three sizes.
    public var complexity: Complexity?

    public init(
      id: ReportID,
      scope: ReportScope,
      metric: Benchmark.Metric,
      statistic: Statistic,
      points: [Point],
      complexity: Complexity? = nil
    ) {
      self.id = id
      self.scope = scope
      self.metric = metric
      self.statistic = statistic
      self.points = points
      self.complexity = complexity
    }
  }
}

extension Report.DimensionCurve {
  public struct Point: Sendable, Equatable, Codable {
    public var size: Benchmark.Scale
    /// The statistic's value at this size, in the metric's unit.
    public var value: Double
    /// ``value`` divided by ``size``.
    public var amortizedPerUnit: Double
    public var sampleCount: Int
    public var sourceLocation: SourceLocationReport?

    public init(
      size: Benchmark.Scale,
      value: Double,
      amortizedPerUnit: Double,
      sampleCount: Int,
      sourceLocation: SourceLocationReport? = nil
    ) {
      self.size = size
      self.value = value
      self.amortizedPerUnit = amortizedPerUnit
      self.sampleCount = sampleCount
      self.sourceLocation = sourceLocation
    }
  }
}

extension Report.DimensionCurve {
  /// The statistics a report draws a curve for, for every metric of a case
  /// that has Dimension rows.
  static let statistics: [Report.Statistic] = [.mean, .median, .p95]

  static func curves(
    suiteName: String,
    caseName: String,
    scope: ReportScope,
    measurement: Report.Measurement,
    sourceLocation: SourceLocationReport?
  ) -> [Report.DimensionCurve] {
    let rows = measurement.rows.filter { $0.size != nil }
    guard !rows.isEmpty else {
      return []
    }
    return measurement.metrics.flatMap { metric in
      statistics.map { statistic in
        let curveID = ReportIDFactory.dimensionCurve(
          suiteName: suiteName,
          caseName: caseName,
          metric: metric,
          statistic: statistic
        )
        let points = rows.compactMap { row -> Point? in
          guard let size = row.size, let statistics = row.statistics(for: metric) else {
            return nil
          }
          let value = statistic.value(from: statistics)
          return Point(
            size: size,
            value: value,
            amortizedPerUnit: Benchmark.Dimension.amortized(value, by: size),
            sampleCount: statistics.count,
            sourceLocation: sourceLocation
          )
        }
        return Report.DimensionCurve(
          id: curveID,
          scope: ReportScope(
            runID: scope.runID,
            suiteID: scope.suiteID,
            caseID: scope.caseID,
            dimensionCurveID: curveID
          ),
          metric: metric,
          statistic: statistic,
          points: points,
          complexity: Report.Complexity.fit(
            points.map { (size: Double($0.size.rawValue), value: $0.value) })
        )
      }
    }
  }
}
