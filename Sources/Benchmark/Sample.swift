public struct Sample: Sendable, Equatable {
  public let iteration: Int
  public let durationNanoseconds: UInt64

  public init(iteration: Int, durationNanoseconds: UInt64) {
    self.iteration = iteration
    self.durationNanoseconds = durationNanoseconds
  }
}
