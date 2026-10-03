// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkResult: Sendable, Equatable {
  public let suiteName: String
  public let caseName: String
  public let sourceLocation: BenchmarkSourceLocation?
  public let configuration: BenchmarkConfiguration
  public let tags: [String]
  public let measurement: Measurement

  public init(
    suiteName: String,
    caseName: String,
    sourceLocation: BenchmarkSourceLocation? = nil,
    configuration: BenchmarkConfiguration,
    tags: [String] = [],
    measurement: Measurement
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.sourceLocation = sourceLocation
    self.configuration = configuration
    self.tags = tags
    self.measurement = measurement
  }
}
