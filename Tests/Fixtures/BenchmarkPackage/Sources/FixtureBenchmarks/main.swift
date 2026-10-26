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

  @Benchmark("Allocate1000")
  func allocate1000() {
    for _ in 0..<1_000 {
      blackHole(AllocationProbe())
    }
  }

  @Benchmark("Touch64MiB")
  func touch64MiB() {
    var buffer = [UInt8](repeating: 1, count: 64 << 20)
    buffer[buffer.count / 2] = 2
    blackHole(buffer)
  }
}

/// A heap object of known size: a 16-byte object header and one `Int`.
final class AllocationProbe {
  var value = 0
}

@main
struct FixtureBenchmarkHost {
  static func main() async {
    await BenchmarkHost.run(discoveries: [FixtureBenchmarks.self])
  }
}
