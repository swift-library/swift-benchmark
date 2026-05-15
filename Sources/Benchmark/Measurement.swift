public typealias Measurement = Benchmark.Measurement

public extension Benchmark {
  struct Measurement: Sendable, Equatable {
    public var rows: [Row]

    public init(rows: [Row]) {
      self.rows = rows
    }

    public init(samples: [Sample]) {
      self.init(rows: [Row(size: nil, arguments: [], samples: samples)])
    }

    public var samples: [Sample] {
      rows.flatMap(\.samples)
    }
  }
}

public extension Benchmark.Measurement {
  struct Row: Sendable, Equatable {
    public var id: String?
    public var size: Benchmark.Scale?
    public var arguments: [Benchmark.ArgumentValue]
    public var samples: [Sample]

    public init(
      id: String? = nil,
      size: Benchmark.Scale?,
      arguments: [Benchmark.ArgumentValue] = [],
      samples: [Sample]
    ) {
      self.id = id
      self.size = size
      self.arguments = arguments
      self.samples = samples
    }
  }
}
