// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public protocol _BenchmarkDiscovery: Sendable {
  // Discovery macros and generated hosts share this witness name.
  // swift-format-ignore: AlwaysUseLowerCamelCase
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
