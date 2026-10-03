// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

@BenchmarkSuite("LibraryFixture", .tag("library"))
struct LibraryFixtureBenchmarks {
  @Benchmark("Noop", .tag("fast"))
  func noop() {
    blackHole(1)
  }
}
