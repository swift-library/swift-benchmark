// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import Benchmark
import Instruments

@InstrumentedMembers
public struct ReleaseWorkload {
  public init() {}

  public func evaluate(_ scale: Int) -> Int {
    #span("consumer.nested") {
      #event("consumer.event")
      return scale * 2
    }
  }
}

@BenchmarkSuite(
  "ReleaseLibrary",
  .configuration(.init(warmup: .iterations(1), iterations: .iterations(3)))
)
struct ReleaseLibraryBenchmarks {
  @Benchmark("Instrumented Workload")
  func workload() {
    blackHole(ReleaseWorkload().evaluate(2))
  }
}
