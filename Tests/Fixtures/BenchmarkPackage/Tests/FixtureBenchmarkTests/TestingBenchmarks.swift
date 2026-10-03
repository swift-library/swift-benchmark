// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import BenchmarkTesting
import BenchmarkXCTest
import Foundation
import Testing

extension Tag {
  @Tag static var testingBridge: Self
  @Tag static var standalone: Self
}

@Suite(
  "TestingFixture",
  .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
  .tags(.testingBridge)
)
struct FixtureBenchmarkTestingSuite {
  @Test("Suite Noop")
  func suiteNoop() {
    blackHole(BenchmarkXCTestAdapter())
    blackHole(3)
  }

  @Test(
    "Case Override",
    .benchmark(configuration: .init(warmup: .none, iterations: .iterations(2)))
  )
  func caseOverride() {
    blackHole(4)
  }
}

struct StandaloneTestingBenchmarks {
  @Test(
    "Foundation Resource Keys",
    .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
    .tags(.standalone)
  )
  func foundationResourceKeys() {
    blackHole(Set<URLResourceKey>([.isDirectoryKey, .nameKey]))
  }

  @Test(
    "Standalone Testing Benchmark",
    .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
    .tags(.standalone)
  )
  func standalone() {
    blackHole(5)
  }

  @Test("Plain Test")
  func plainTestIsNotBenchmark() {
    blackHole(6)
  }
}
