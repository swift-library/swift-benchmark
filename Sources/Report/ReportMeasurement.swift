import Benchmark

public enum Report {}

public extension Report {
  struct Measurement: Sendable, Equatable, Codable {
    public var rows: [Row]

    public init(rows: [Row]) {
      self.rows = rows
    }

    public init(samples: [SampleReport]) {
      self.init(rows: [Row(size: nil, samples: samples)])
    }

    public var samples: [SampleReport] {
      rows.flatMap(\.samples)
    }

    public var metrics: Metrics {
      Metrics(samples: samples)
    }
  }
}

public extension Report.Measurement {
  struct Row: Sendable, Equatable, Codable {
    public var size: Benchmark.Dimension.Size?
    public var samples: [SampleReport]
    public var metrics: Metrics
    public var amortized: Metrics?

    public init(
      size: Benchmark.Dimension.Size?,
      samples: [SampleReport],
      metrics: Metrics? = nil,
      amortized: Metrics? = nil
    ) {
      let computedMetrics = metrics ?? Metrics(samples: samples)
      self.size = size
      self.samples = samples
      self.metrics = computedMetrics
      self.amortized = amortized ?? size.map { computedMetrics.amortized(by: $0) }
    }
  }

  struct Metrics: Sendable, Equatable, Codable {
    public var count: Int
    public var min: Double
    public var max: Double
    public var mean: Double
    public var median: Double
    public var standardDeviation: Double
    public var p90: Double
    public var p95: Double
    public var p99: Double

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

    public init(samples: [SampleReport]) {
      self.init(values: samples.map { Double($0.durationNanoseconds) })
    }

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
      let variance = values.reduce(0) { partial, value in
        let delta = value - meanValue
        return partial + delta * delta
      } / Double(values.count)
      self.standardDeviation = variance.squareRoot()
      self.p90 = Self.percentile(0.90, values: values)
      self.p95 = Self.percentile(0.95, values: values)
      self.p99 = Self.percentile(0.99, values: values)
    }

    public func amortized(by size: Benchmark.Dimension.Size) -> Metrics {
      let divisor = Double(size.rawValue)
      guard divisor != 0 else {
        return self
      }
      return Metrics(
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

  enum Metric: String, Sendable, Codable, CaseIterable {
    case min
    case max
    case mean
    case median
    case standardDeviation
    case p90
    case p95
    case p99

    public func value(from metrics: Metrics) -> Double {
      switch self {
      case .min:
        return metrics.min
      case .max:
        return metrics.max
      case .mean:
        return metrics.mean
      case .median:
        return metrics.median
      case .standardDeviation:
        return metrics.standardDeviation
      case .p90:
        return metrics.p90
      case .p95:
        return metrics.p95
      case .p99:
        return metrics.p99
      }
    }
  }
}

public extension Report {
  struct DimensionCurve: Sendable, Equatable, Codable {
    public var id: ReportID
    public var scope: ReportScope
    public var metric: Measurement.Metric
    public var points: [Point]

    public init(
      id: ReportID,
      scope: ReportScope,
      metric: Measurement.Metric,
      points: [Point]
    ) {
      self.id = id
      self.scope = scope
      self.metric = metric
      self.points = points
    }
  }
}

public extension Report.DimensionCurve {
  struct Point: Sendable, Equatable, Codable {
    public var size: Benchmark.Dimension.Size
    public var valueNanoseconds: Double
    public var amortizedNanosecondsPerUnit: Double
    public var sampleCount: Int
    public var sourceLocation: SourceLocationReport?

    public init(
      size: Benchmark.Dimension.Size,
      valueNanoseconds: Double,
      amortizedNanosecondsPerUnit: Double,
      sampleCount: Int,
      sourceLocation: SourceLocationReport? = nil
    ) {
      self.size = size
      self.valueNanoseconds = valueNanoseconds
      self.amortizedNanosecondsPerUnit = amortizedNanosecondsPerUnit
      self.sampleCount = sampleCount
      self.sourceLocation = sourceLocation
    }
  }
}
