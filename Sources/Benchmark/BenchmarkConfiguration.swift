// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkConfiguration: Sendable, Equatable {
  public static let `default` = BenchmarkConfiguration()

  public var warmup: WarmupPolicy
  public var iterations: IterationPolicy
  /// How many calls each sample measures.
  public var batching: BatchingPolicy

  /// Creates a configuration; the defaults warm up once, measure ten samples
  /// and batch automatically.
  public init(
    warmup: WarmupPolicy = .iterations(1),
    iterations: IterationPolicy = .iterations(10),
    batching: BatchingPolicy = .automatic()
  ) {
    self.warmup = warmup
    self.iterations = iterations
    self.batching = batching
  }

  public func validatedCounts() throws -> (warmup: Int, iterations: Int) {
    let warmupCount = try warmup.validatedCount()
    let iterationCount = try iterations.validatedPlan().maxIterations
    return (warmupCount, iterationCount)
  }

  public func validatedExecutionPolicy() throws -> BenchmarkExecutionPolicy {
    BenchmarkExecutionPolicy(
      warmupCount: try warmup.validatedCount(),
      iterations: try iterations.validatedPlan(),
      batching: try batching.validated()
    )
  }
}

public struct BenchmarkExecutionPolicy: Sendable, Equatable {
  public var warmupCount: Int
  public var iterations: IterationPlan
  /// How many calls each sample measures.
  public var batching: BatchingPolicy

  /// Creates a validated policy.
  public init(
    warmupCount: Int,
    iterations: IterationPlan,
    batching: BatchingPolicy = .fixed(1)
  ) {
    self.warmupCount = warmupCount
    self.iterations = iterations
    self.batching = batching
  }
}

/// How many consecutive calls of the workload one sample measures.
///
/// Batching keeps clock reads and per-sample overhead small relative to the
/// measured time, so short workloads are measured accurately. Every metric is
/// reported per call.
public enum BatchingPolicy: Sendable, Equatable, CustomStringConvertible {
  /// Chooses the batch size so a sample lasts at least `targetNanoseconds`,
  /// calling the workload at most `maxBatchSize` times per sample.
  case automatic(targetNanoseconds: UInt64 = 1_000_000, maxBatchSize: Int = 1_000_000)
  /// Calls the workload `count` times per sample.
  case fixed(Int)

  public var description: String {
    switch self {
    case .automatic(let targetNanoseconds, let maxBatchSize):
      return "automatic(targetNanoseconds: \(targetNanoseconds), maxBatchSize: \(maxBatchSize))"
    case .fixed(let count):
      return "fixed(\(count))"
    }
  }

  func validated() throws -> BatchingPolicy {
    switch self {
    case .automatic(let targetNanoseconds, let maxBatchSize):
      guard targetNanoseconds > 0, maxBatchSize > 0 else {
        throw BenchmarkRunnerError.invalidConfiguration(
          "Automatic batching needs a positive target duration and maximum batch size."
        )
      }
    case .fixed(let count):
      guard count > 0 else {
        throw BenchmarkRunnerError.invalidConfiguration("Batch size must be positive.")
      }
    }
    return self
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
    let elapsed = samples.reduce(0.0) { total, sample in
      total + (sample.value(for: .wallClock) ?? 0) * Double(sample.batchSize)
    }
    if let maxDurationNanoseconds, elapsed >= Double(maxDurationNanoseconds) {
      return false
    }
    if let minDurationNanoseconds {
      return elapsed < Double(minDurationNanoseconds)
    }
    return kind == .adaptive
  }
}
