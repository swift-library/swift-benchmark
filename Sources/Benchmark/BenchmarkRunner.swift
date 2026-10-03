// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct BenchmarkRunner: Sendable {
  public let clock: any BenchmarkClock

  public init(clock: any BenchmarkClock = ContinuousBenchmarkClock()) {
    self.clock = clock
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
      let row = try await runRow(
        step: step,
        suite: step.suite,
        policy: policy,
        observers: observers,
        eventRecorders: eventRecorders
      )
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

  private func runRow(
    step: Plan.Step,
    suite: BenchmarkSuite,
    policy: BenchmarkExecutionPolicy,
    observers: [any BenchmarkExecutionObserver],
    eventRecorders: [any BenchmarkEventRecorder]
  ) async throws -> Benchmark.Measurement.Row {
    await record(
      kind: .dimensionRowStarted,
      context: Benchmark.Event.Context(step: step),
      eventRecorders: eventRecorders
    )
    let operation: @Sendable () async throws -> Void
    do {
      guard step.action.isMeasure, let row = step.caseRow else {
        throw BenchmarkRunnerError.invalidConfiguration(
          "Step '\(step.id)' does not contain a measurement row."
        )
      }
      operation = try await row.makeOperation()
    } catch {
      throw BenchmarkRunnerError.caseFailed(
        suite: suite.name,
        case: step.benchmarkCase.name,
        phase: .dimensionSetup(size: step.size),
        underlying: error
      )
    }

    for iteration in 0..<policy.warmupCount {
      let context = BenchmarkExecutionContext(
        suiteName: suite.name,
        caseName: step.benchmarkCase.name,
        size: step.size,
        arguments: step.arguments,
        phase: .warmup(iteration: iteration)
      )
      await record(
        kind: .warmupStarted,
        context: Benchmark.Event.Context(
          step: step, iteration: iteration, phase: .warmup(iteration: iteration)),
        eventRecorders: eventRecorders
      )
      await notifyWillRun(context: context, observers: observers)
      do {
        try await operation()
        await notifyDidRun(context: context, durationNanoseconds: nil, observers: observers)
        await record(
          kind: .warmupEnded,
          context: Benchmark.Event.Context(
            step: step, iteration: iteration, phase: .warmup(iteration: iteration)),
          eventRecorders: eventRecorders
        )
      } catch {
        await notifyDidFail(context: context, error: error, observers: observers)
        await record(
          kind: .issueRecorded,
          context: Benchmark.Event.Context(
            step: step, iteration: iteration, phase: .warmup(iteration: iteration),
            message: String(describing: error)),
          eventRecorders: eventRecorders
        )
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name,
          case: step.benchmarkCase.name,
          phase: .warmup(iteration: iteration),
          underlying: error
        )
      }
    }

    var samples: [Sample] = []
    samples.reserveCapacity(policy.iterations.maxIterations)
    while policy.iterations.shouldContinue(after: samples) {
      let iteration = samples.count
      let context = BenchmarkExecutionContext(
        suiteName: suite.name,
        caseName: step.benchmarkCase.name,
        size: step.size,
        arguments: step.arguments,
        phase: .measurement(iteration: iteration)
      )
      await record(
        kind: .iterationStarted,
        context: Benchmark.Event.Context(
          step: step, iteration: iteration, phase: .measurement(iteration: iteration)),
        eventRecorders: eventRecorders
      )
      await notifyWillRun(context: context, observers: observers)
      let start = clock.now()
      do {
        try await operation()
      } catch {
        await notifyDidFail(context: context, error: error, observers: observers)
        await record(
          kind: .issueRecorded,
          context: Benchmark.Event.Context(
            step: step, iteration: iteration, phase: .measurement(iteration: iteration),
            message: String(describing: error)),
          eventRecorders: eventRecorders
        )
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name,
          case: step.benchmarkCase.name,
          phase: .measurement(iteration: iteration),
          underlying: error
        )
      }
      let end = clock.now()
      let duration = start.duration(to: end)
      samples.append(
        Sample(iteration: iteration, durationNanoseconds: duration)
      )
      await record(
        kind: .sampleRecorded,
        context: Benchmark.Event.Context(
          step: step,
          iteration: iteration,
          phase: .measurement(iteration: iteration),
          durationNanoseconds: duration
        ),
        eventRecorders: eventRecorders
      )
      await notifyDidRun(context: context, durationNanoseconds: duration, observers: observers)
      await record(
        kind: .iterationEnded,
        context: Benchmark.Event.Context(
          step: step,
          iteration: iteration,
          phase: .measurement(iteration: iteration),
          durationNanoseconds: duration
        ),
        eventRecorders: eventRecorders
      )
    }

    await record(
      kind: .dimensionRowEnded,
      context: Benchmark.Event.Context(step: step),
      eventRecorders: eventRecorders
    )
    return Benchmark.Measurement.Row(
      id: step.argumentRow?.id,
      size: step.size,
      arguments: step.arguments,
      samples: samples
    )
  }

  private func notifyWillRun(
    context: BenchmarkExecutionContext,
    observers: [any BenchmarkExecutionObserver]
  ) async {
    for observer in observers {
      await observer.benchmarkWillRun(context: context)
    }
  }

  private func notifyDidRun(
    context: BenchmarkExecutionContext,
    durationNanoseconds: UInt64?,
    observers: [any BenchmarkExecutionObserver]
  ) async {
    for observer in observers {
      await observer.benchmarkDidRun(context: context, durationNanoseconds: durationNanoseconds)
    }
  }

  private func notifyDidFail(
    context: BenchmarkExecutionContext,
    error: any Error,
    observers: [any BenchmarkExecutionObserver]
  ) async {
    for observer in observers {
      await observer.benchmarkDidFail(context: context, error: error)
    }
  }

  private func record(
    kind: Benchmark.Event.Kind,
    context: Benchmark.Event.Context,
    eventRecorders: [any BenchmarkEventRecorder]
  ) async {
    guard !eventRecorders.isEmpty else {
      return
    }
    let record = Benchmark.Event.Stream.Record(kind: kind, context: context)
    for eventRecorder in eventRecorders {
      await eventRecorder.record(record)
    }
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
  case measurement(iteration: Int)
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
