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
