// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkSuite: Sendable {
  public let name: String
  public let configuration: BenchmarkConfiguration
  public let traits: [any BenchmarkSuiteTrait]
  public let cases: [BenchmarkCase]

  public init(
    _ name: String,
    configuration: BenchmarkConfiguration = .default,
    traits: [any BenchmarkSuiteTrait] = [],
    cases: [BenchmarkCase] = []
  ) {
    self.name = name
    self.configuration = configuration
    self.traits = traits
    self.cases = cases
  }

  public init(
    _ name: String,
    configuration: BenchmarkConfiguration = .default,
    traits: [any BenchmarkSuiteTrait] = [],
    @BenchmarkBuilder _ cases: () -> [BenchmarkCase]
  ) {
    self.init(name, configuration: configuration, traits: traits, cases: cases())
  }
}
