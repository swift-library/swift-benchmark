// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import BenchmarkTesting
import Testing

struct PrivateBenchmarks {
  @Test(.benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))))
  private func privateBenchmark() {
    blackHole(1)
  }
}
