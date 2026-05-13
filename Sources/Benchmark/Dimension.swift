public extension Benchmark {
  struct Dimension: Sendable, Equatable {
    public var sizes: [Size]

    public init(sizes: [Size]) {
      self.sizes = sizes
    }

    public init(sizes: [Int]) {
      self.init(sizes: sizes.map(Size.init))
    }

    public static func amortized(_ value: Double, by size: Size) -> Double {
      guard size.rawValue > 0 else {
        return 0
      }
      return value / Double(size.rawValue)
    }
  }
}

public extension Benchmark.Dimension {
  struct Size: Sendable, Equatable, Hashable, Comparable, Codable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
      self.rawValue = rawValue
    }

    public static func < (lhs: Size, rhs: Size) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
}
