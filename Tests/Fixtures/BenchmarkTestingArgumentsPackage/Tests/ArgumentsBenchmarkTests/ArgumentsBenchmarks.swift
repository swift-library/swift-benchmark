// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import BenchmarkTesting
import Testing

struct ArgumentsBenchmarks {
  @Test(
    .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
    arguments: [1, 2]
  )
  func argumentBenchmark(value: Int) {
    blackHole(value)
  }
}
