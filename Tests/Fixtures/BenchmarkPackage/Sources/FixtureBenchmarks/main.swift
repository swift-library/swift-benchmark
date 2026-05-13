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
