// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Testing

@Suite("Benchmark blackHole")
struct BlackHoleTests {
  @Test
  func blackHoleAcceptsValues() {
    blackHole(1)
    blackHole("value")
  }
}
