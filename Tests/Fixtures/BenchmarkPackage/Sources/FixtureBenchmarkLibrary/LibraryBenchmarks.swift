import Benchmark

@BenchmarkSuite("LibraryFixture", .tag("library"))
struct LibraryFixtureBenchmarks {
  @Benchmark("Noop", .tag("fast"))
  func noop() {
    blackHole(1)
  }
}
