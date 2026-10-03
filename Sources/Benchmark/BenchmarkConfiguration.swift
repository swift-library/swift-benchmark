// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkConfiguration: Sendable, Equatable {
  public static let `default` = BenchmarkConfiguration()

  public var warmup: WarmupPolicy
  public var iterations: IterationPolicy

  public init(
    warmup: WarmupPolicy = .iterations(1),
    iterations: IterationPolicy = .iterations(10)
  ) {
    self.warmup = warmup
    self.iterations = iterations
  }

  public func validatedCounts() throws -> (warmup: Int, iterations: Int) {
    let warmupCount = try warmup.validatedCount()
    let iterationCount = try iterations.validatedPlan().maxIterations
    return (warmupCount, iterationCount)
  }

  public func validatedExecutionPolicy() throws -> BenchmarkExecutionPolicy {
    BenchmarkExecutionPolicy(
      warmupCount: try warmup.validatedCount(),
      iterations: try iterations.validatedPlan()
    )
  }
}

public struct BenchmarkExecutionPolicy: Sendable, Equatable {
  public var warmupCount: Int
  public var iterations: IterationPlan

  public init(warmupCount: Int, iterations: IterationPlan) {
    self.warmupCount = warmupCount
    self.iterations = iterations
  }
}

public enum WarmupPolicy: Sendable, Equatable {
  case none
  case iterations(Int)

  func validatedCount() throws -> Int {
    switch self {
    case .none:
      return 0
    case .iterations(let count):
      guard count >= 0 else {
        throw BenchmarkRunnerError.invalidConfiguration("Warmup iterations must be nonnegative.")
      }
      return count
    }
  }
}

public enum IterationPolicy: Sendable, Equatable {
  case iterations(Int)
  case adaptive(
    minIterations: Int = 1,
    maxIterations: Int = 100,
    minDurationNanoseconds: UInt64? = nil,
    maxDurationNanoseconds: UInt64? = nil
  )

  func validatedPlan() throws -> IterationPlan {
    switch self {
    case .iterations(let count):
      guard count > 0 else {
        throw BenchmarkRunnerError.invalidConfiguration("Measured iterations must be positive.")
      }
      return IterationPlan(
        kind: .fixed,
        minIterations: count,
        maxIterations: count
      )
    case .adaptive(
      let minIterations,
      let maxIterations,
      let minDurationNanoseconds,
      let maxDurationNanoseconds
    ):
      guard minIterations > 0 else {
        throw BenchmarkRunnerError.invalidConfiguration("Adaptive minIterations must be positive.")
      }
      guard maxIterations >= minIterations else {
        throw BenchmarkRunnerError.invalidConfiguration(
          "Adaptive maxIterations must be greater than or equal to minIterations."
        )
      }
      if let minDurationNanoseconds, let maxDurationNanoseconds,
        minDurationNanoseconds > maxDurationNanoseconds
      {
        throw BenchmarkRunnerError.invalidConfiguration(
          "Adaptive minDurationNanoseconds must be less than or equal to maxDurationNanoseconds."
        )
      }
      return IterationPlan(
        kind: .adaptive,
        minIterations: minIterations,
        maxIterations: maxIterations,
        minDurationNanoseconds: minDurationNanoseconds,
        maxDurationNanoseconds: maxDurationNanoseconds
      )
    }
  }
}

public struct IterationPlan: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case fixed
    case adaptive
  }

  public var kind: Kind
  public var minIterations: Int
  public var maxIterations: Int
  public var minDurationNanoseconds: UInt64?
  public var maxDurationNanoseconds: UInt64?

  public init(
    kind: Kind,
    minIterations: Int,
    maxIterations: Int,
    minDurationNanoseconds: UInt64? = nil,
    maxDurationNanoseconds: UInt64? = nil
  ) {
    self.kind = kind
    self.minIterations = minIterations
    self.maxIterations = maxIterations
    self.minDurationNanoseconds = minDurationNanoseconds
    self.maxDurationNanoseconds = maxDurationNanoseconds
  }

  func shouldContinue(after samples: [Sample]) -> Bool {
    guard samples.count < maxIterations else {
      return false
    }
    guard samples.count >= minIterations else {
      return true
    }
    let elapsed = samples.reduce(UInt64(0)) { $0 + $1.durationNanoseconds }
    if let maxDurationNanoseconds, elapsed >= maxDurationNanoseconds {
      return false
    }
    if let minDurationNanoseconds {
      return elapsed < minDurationNanoseconds
    }
    return kind == .adaptive
  }
}
