// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension Benchmark {
  public struct Scale: Sendable, Equatable, Hashable, Comparable, Codable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
      self.rawValue = rawValue
    }

    public static func < (lhs: Scale, rhs: Scale) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
}

extension Benchmark {
  public struct Dimension: Sendable, Equatable {
    public var sizes: [Benchmark.Scale]

    public init(sizes: [Benchmark.Scale]) {
      self.sizes = sizes
    }

    public init(sizes: [Int]) {
      self.init(sizes: sizes.map(Benchmark.Scale.init))
    }

    public static func amortized(_ value: Double, by size: Benchmark.Scale) -> Double {
      guard size.rawValue > 0 else {
        return 0
      }
      return value / Double(size.rawValue)
    }
  }
}
