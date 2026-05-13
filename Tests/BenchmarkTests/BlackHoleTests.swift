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
