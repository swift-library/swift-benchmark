// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkRunner: Sendable {
  public let clock: any BenchmarkClock
  /// Reads CPU time for ``Benchmark/Metric/cpuTime``; `nil` leaves the metric out.
  public let cpuClock: (any BenchmarkClock)?
  /// Whether each step ends with a pass that counts Swift heap allocations and
  /// reference-counting operations.
  public let countsAllocations: Bool
  /// Whether each step records ``Benchmark/Metric/peakMemory``. Enable it only
  /// when the process measures a single step, because the footprint peak
  /// covers the whole process lifetime.
  public let recordsPeakMemory: Bool

  /// Creates a runner. The defaults measure wall-clock time, CPU time and
  /// allocation counts, and leave out peak memory.
  public init(
    clock: any BenchmarkClock = ContinuousBenchmarkClock(),
    cpuClock: (any BenchmarkClock)? = ProcessCPUClock(),
    countsAllocations: Bool = true,
    recordsPeakMemory: Bool = false
  ) {
    self.clock = clock
    self.cpuClock = cpuClock
    self.countsAllocations = countsAllocations
    self.recordsPeakMemory = recordsPeakMemory
  }

  public func run(
    _ suite: BenchmarkSuite,
    observers: [any BenchmarkExecutionObserver] = [],
    eventRecorders: [any BenchmarkEventRecorder] = []
  ) async throws -> [BenchmarkResult] {
    try await run(Plan(suites: [suite]), observers: observers, eventRecorders: eventRecorders)
  }

  public func run(
    _ suites: [BenchmarkSuite],
    observers: [any BenchmarkExecutionObserver] = [],
    eventRecorders: [any BenchmarkEventRecorder] = []
  ) async throws -> [BenchmarkResult] {
    try await run(Plan(suites: suites), observers: observers, eventRecorders: eventRecorders)
  }

  public func run(
    _ plan: Plan,
    observers: [any BenchmarkExecutionObserver] = [],
    eventRecorders: [any BenchmarkEventRecorder] = []
  ) async throws -> [BenchmarkResult] {
    var accumulators: [CaseKey: CaseAccumulator] = [:]
    var order: [CaseKey] = []
    await record(
      kind: .planStarted,
      context: Benchmark.Event.Context(),
      eventRecorders: eventRecorders
    )

    for step in plan.steps {
      switch step.action {
      case .skip(let reason):
        await record(
          kind: .skipped,
          context: Benchmark.Event.Context(step: step, message: reason),
          eventRecorders: eventRecorders
        )
        continue
      case .planningFailure(let issue):
        await record(
          kind: .issueRecorded,
          context: Benchmark.Event.Context(step: step, message: issue.description),
          eventRecorders: eventRecorders
        )
        throw BenchmarkRunnerError.invalidConfiguration(issue.description)
      case .measure:
        break
      }

      let policy: BenchmarkExecutionPolicy
      do {
        policy = try step.configuration.validatedExecutionPolicy()
      } catch {
        throw BenchmarkRunnerError.caseFailed(
          suite: step.suiteName,
          case: step.caseName,
          phase: .configuration,
          underlying: error
        )
      }

      await record(
        kind: .caseStarted,
        context: Benchmark.Event.Context(step: step),
        eventRecorders: eventRecorders
      )
      let row = try await MeasurementGate.shared.withExclusiveAccess {
        try await runRow(
          step: step,
          suite: step.suite,
          policy: policy,
          observers: observers,
          eventRecorders: eventRecorders
        )
      }
      await record(
        kind: .caseEnded,
        context: Benchmark.Event.Context(step: step),
        eventRecorders: eventRecorders
      )
      let key = CaseKey(suiteName: step.suiteName, caseName: step.caseName)
      if accumulators[key] == nil {
        order.append(key)
        accumulators[key] = CaseAccumulator(
          suiteName: step.suiteName,
          caseName: step.caseName,
          sourceLocation: step.benchmarkCase.sourceLocation,
          configuration: step.configuration,
          tags: step.tags,
          rows: []
        )
      }
      accumulators[key]?.rows.append(row)
    }

    let results: [BenchmarkResult] = order.compactMap { key in
      guard let accumulator = accumulators[key] else {
        return nil
      }
      return BenchmarkResult(
        suiteName: accumulator.suiteName,
        caseName: accumulator.caseName,
        sourceLocation: accumulator.sourceLocation,
        configuration: accumulator.configuration,
        tags: accumulator.tags,
        measurement: Measurement(rows: accumulator.rows)
      )
    }
    await record(
      kind: .planEnded,
      context: Benchmark.Event.Context(),
      eventRecorders: eventRecorders
    )
    return results
  }
}

private struct CaseKey: Hashable {
  var suiteName: String
  var caseName: String
}

private struct CaseAccumulator {
  var suiteName: String
  var caseName: String
  var sourceLocation: BenchmarkSourceLocation?
  var configuration: BenchmarkConfiguration
  var tags: [String]
  var rows: [Benchmark.Measurement.Row]
}

public enum BenchmarkPhase: Sendable, Equatable {
  case configuration
  case dimensionSetup(size: Benchmark.Scale?)
  case warmup(iteration: Int)
  case calibration
  case measurement(iteration: Int)
  case counting
}

public enum BenchmarkRunnerError: Error, CustomStringConvertible {
  case invalidConfiguration(String)
  case caseFailed(suite: String, case: String, phase: BenchmarkPhase, underlying: any Error)

  public var description: String {
    switch self {
    case .invalidConfiguration(let message):
      return message
    case .caseFailed(let suiteName, let caseName, let phase, let underlying):
      return "Benchmark '\(suiteName).\(caseName)' failed during \(phase): \(underlying)"
    }
  }
}
