import Benchmark
import BenchmarkTesting
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
