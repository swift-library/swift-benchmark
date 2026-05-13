public protocol BenchmarkClock: Sendable {
  func now() -> BenchmarkInstant
}

public struct BenchmarkInstant: Sendable, Equatable, Comparable {
  public let nanoseconds: UInt64

  public init(nanoseconds: UInt64) {
    self.nanoseconds = nanoseconds
  }

  public func duration(to other: BenchmarkInstant) -> UInt64 {
    other.nanoseconds >= nanoseconds ? other.nanoseconds - nanoseconds : 0
  }

  public static func < (lhs: BenchmarkInstant, rhs: BenchmarkInstant) -> Bool {
    lhs.nanoseconds < rhs.nanoseconds
  }
}

public struct ContinuousBenchmarkClock: BenchmarkClock {
  private let clock: ContinuousClock
  private let origin: ContinuousClock.Instant

  public init() {
    let clock = ContinuousClock()
    self.clock = clock
    self.origin = clock.now
  }

  public func now() -> BenchmarkInstant {
    let duration = origin.duration(to: clock.now)
    let components = duration.components
    let seconds = components.seconds >= 0 ? UInt64(components.seconds) : 0
    let attoseconds = components.attoseconds >= 0 ? UInt64(components.attoseconds) : 0
    return BenchmarkInstant(
      nanoseconds: seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    )
  }
}
