import Benchmark
import BenchmarkTesting
import Testing

struct PrivateBenchmarks {
  @Test(.benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))))
  private func privateBenchmark() {
    blackHole(1)
  }
}
