public enum BenchmarkScoping: Sendable, Equatable {
  case recursive
  case local
}

public protocol BenchmarkTrait: Sendable {
  var benchmarkConfiguration: BenchmarkConfiguration? { get }
  var benchmarkSkipReason: String? { get }
  var benchmarkTags: [String] { get }
}

public extension BenchmarkTrait {
  var benchmarkConfiguration: BenchmarkConfiguration? { nil }
  var benchmarkSkipReason: String? { nil }
  var benchmarkTags: [String] { [] }
}

public protocol BenchmarkSuiteTrait: BenchmarkTrait {
  var benchmarkScoping: BenchmarkScoping { get }
}

public extension BenchmarkSuiteTrait {
  var benchmarkScoping: BenchmarkScoping { .recursive }
}

public protocol BenchmarkCaseTrait: BenchmarkTrait {
  var benchmarkDimension: Benchmark.Dimension? { get }
}

public extension BenchmarkCaseTrait {
  var benchmarkDimension: Benchmark.Dimension? { nil }
}

public enum BenchmarkTraitValue: Sendable, Equatable {
  case configuration(BenchmarkConfiguration)
  case dimension(Benchmark.Dimension)
  case skip(String)
  case tag(String)
}

public struct BenchmarkConfigurationTrait: BenchmarkSuiteTrait, BenchmarkCaseTrait, Equatable {
  public var configuration: BenchmarkConfiguration

  public init(_ configuration: BenchmarkConfiguration) {
    self.configuration = configuration
  }

  public var benchmarkConfiguration: BenchmarkConfiguration? {
    configuration
  }
}

public extension Benchmark.Dimension {
  struct Trait: BenchmarkCaseTrait, Equatable {
    public var dimension: Benchmark.Dimension

    public init(_ dimension: Benchmark.Dimension) {
      self.dimension = dimension
    }

    public var benchmarkDimension: Benchmark.Dimension? {
      dimension
    }
  }
}

public struct BenchmarkSkipTrait: BenchmarkSuiteTrait, BenchmarkCaseTrait, Equatable {
  public var reason: String
  public var scoping: BenchmarkScoping

  public init(_ reason: String, scoping: BenchmarkScoping = .recursive) {
    self.reason = reason
    self.scoping = scoping
  }

  public var benchmarkSkipReason: String? {
    reason
  }

  public var benchmarkScoping: BenchmarkScoping {
    scoping
  }
}

public struct BenchmarkTagTrait: BenchmarkSuiteTrait, BenchmarkCaseTrait, Equatable {
  public var tag: String
  public var scoping: BenchmarkScoping

  public init(_ tag: String, scoping: BenchmarkScoping = .recursive) {
    self.tag = tag
    self.scoping = scoping
  }

  public var benchmarkTags: [String] {
    [tag]
  }

  public var benchmarkScoping: BenchmarkScoping {
    scoping
  }
}

public extension BenchmarkCaseTrait where Self == Benchmark.Dimension.Trait {
  static func dimension(sizes: [Int]) -> Benchmark.Dimension.Trait {
    Benchmark.Dimension.Trait(Benchmark.Dimension(sizes: sizes))
  }
}

public extension BenchmarkSuiteTrait where Self == BenchmarkConfigurationTrait {
  static func configuration(_ configuration: BenchmarkConfiguration) -> BenchmarkConfigurationTrait {
    BenchmarkConfigurationTrait(configuration)
  }
}

public extension BenchmarkCaseTrait where Self == BenchmarkConfigurationTrait {
  static func configuration(_ configuration: BenchmarkConfiguration) -> BenchmarkConfigurationTrait {
    BenchmarkConfigurationTrait(configuration)
  }
}

public extension BenchmarkSuiteTrait where Self == BenchmarkSkipTrait {
  static func skip(_ reason: String, scoping: BenchmarkScoping = .recursive) -> BenchmarkSkipTrait {
    BenchmarkSkipTrait(reason, scoping: scoping)
  }
}

public extension BenchmarkCaseTrait where Self == BenchmarkSkipTrait {
  static func skip(_ reason: String) -> BenchmarkSkipTrait {
    BenchmarkSkipTrait(reason, scoping: .local)
  }
}

public extension BenchmarkSuiteTrait where Self == BenchmarkTagTrait {
  static func tag(_ tag: String, scoping: BenchmarkScoping = .recursive) -> BenchmarkTagTrait {
    BenchmarkTagTrait(tag, scoping: scoping)
  }
}

public extension BenchmarkCaseTrait where Self == BenchmarkTagTrait {
  static func tag(_ tag: String) -> BenchmarkTagTrait {
    BenchmarkTagTrait(tag, scoping: .local)
  }
}
