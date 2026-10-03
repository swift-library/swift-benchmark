// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Report

@BenchmarkSuite("Fixture")
struct FixtureBenchmarks {
  @Benchmark("Noop")
  func noop() {
    blackHole(1)
  }

  @Benchmark("Sized")
  func sized() {
    blackHole(2)
  }
}

@main
struct FixtureBenchmarkHost {
  static func main() async throws {
    try await BenchmarkHost.run(discoveries: [FixtureBenchmarks.self])
  }
}
