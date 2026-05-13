public protocol _BenchmarkDiscovery: Sendable {
  static var __benchmarkSuites: [BenchmarkSuite] { get }
}

public struct BenchmarkDiscovery: Sendable {
  public var suites: [BenchmarkSuite]

  public init(suites: [BenchmarkSuite]) {
    self.suites = suites
  }

  public init(_ discoveries: [any _BenchmarkDiscovery.Type]) {
    var suites: [BenchmarkSuite] = []
    for discovery in discoveries {
      suites.append(contentsOf: discovery.__benchmarkSuites)
    }
    self.init(suites: suites)
  }

  public func plan(filter: BenchmarkRunner.Plan.Filter = .all) throws -> BenchmarkRunner.Plan {
    try BenchmarkRunner.Plan(suites: suites, filter: filter)
  }
}
