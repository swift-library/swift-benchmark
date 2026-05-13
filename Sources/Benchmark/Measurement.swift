public typealias Measurement = Benchmark.Measurement

public extension Benchmark {
  struct Measurement: Sendable, Equatable {
    public var rows: [Row]

    public init(rows: [Row]) {
      self.rows = rows
    }

    public init(samples: [Sample]) {
      self.init(rows: [Row(size: nil, samples: samples)])
    }

    public var samples: [Sample] {
      rows.flatMap(\.samples)
    }
  }
}

public extension Benchmark.Measurement {
  struct Row: Sendable, Equatable {
    public var size: Benchmark.Dimension.Size?
    public var samples: [Sample]

    public init(size: Benchmark.Dimension.Size?, samples: [Sample]) {
      self.size = size
      self.samples = samples
    }
  }
}
