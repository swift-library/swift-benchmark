// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
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

  @Benchmark("Leak16Bytes")
  func leak16Bytes() {
    blackHole(UnsafeMutableRawPointer.allocate(byteCount: 16, alignment: 8))
  }

  @Benchmark("SetupAllocates", setup: Self.makeProbe)
  func setupAllocates(_ probe: inout AllocationProbe) {
    probe.value += 1
  }

  static func makeProbe() -> AllocationProbe {
    AllocationProbe()
  }

  /// Four blocks from the Darwin zone's batch allocator; nothing elsewhere.
  @Benchmark("BatchMalloc")
  func batchMalloc() {
    #if canImport(Darwin)
      withUnsafeTemporaryAllocation(of: UnsafeMutableRawPointer?.self, capacity: 4) { blocks in
        let zone = malloc_default_zone()
        let allocated = malloc_zone_batch_malloc(zone, 16, blocks.baseAddress, 4)
        malloc_zone_batch_free(zone, blocks.baseAddress, allocated)
      }
    #endif
  }

  @Benchmark("RunTrue")
  func runTrue() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0)
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
