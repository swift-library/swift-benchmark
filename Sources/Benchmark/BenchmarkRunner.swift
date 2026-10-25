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
    let workload: BenchmarkWorkload
    do {
      guard step.action.isMeasure, let row = step.caseRow else {
        throw BenchmarkRunnerError.invalidConfiguration(
          "Step '\(step.id)' does not contain a measurement row."
        )
      }
      workload = try await row.makeOperation()
    } catch {
      throw BenchmarkRunnerError.caseFailed(
        suite: suite.name,
        case: step.benchmarkCase.name,
        phase: .dimensionSetup(size: step.size),
        underlying: error
      )
    }

    var lastWarmupNanoseconds: UInt64?
    for iteration in 0..<policy.warmupCount {
      let context = executionContext(step: step, suite: suite, phase: .warmup(iteration: iteration))
      await record(
        kind: .warmupStarted,
        context: Benchmark.Event.Context(
          step: step, iteration: iteration, phase: .warmup(iteration: iteration)),
        eventRecorders: eventRecorders
      )
      await notifyWillRun(context: context, observers: observers)
      do {
        let interval = try await workload.callTimed(1, clock: clock)
        lastWarmupNanoseconds = interval.start.duration(to: interval.end)
        await notifyDidRun(context: context, sample: nil, observers: observers)
        await record(
          kind: .warmupEnded,
          context: Benchmark.Event.Context(
            step: step, iteration: iteration, phase: .warmup(iteration: iteration)),
          eventRecorders: eventRecorders
        )
      } catch {
        await notifyDidFail(context: context, error: error, observers: observers)
        await recordIssue(
          error, step: step, iteration: iteration, phase: .warmup(iteration: iteration),
          eventRecorders: eventRecorders)
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name,
          case: step.benchmarkCase.name,
          phase: .warmup(iteration: iteration),
          underlying: error
        )
      }
    }

    let batchSize: Int
    do {
      batchSize = try await calibratedBatchSize(
        workload, policy: policy.batching, lastWarmupNanoseconds: lastWarmupNanoseconds)
    } catch {
      await recordIssue(
        error, step: step, iteration: nil, phase: .calibration, eventRecorders: eventRecorders)
      throw BenchmarkRunnerError.caseFailed(
        suite: suite.name, case: step.benchmarkCase.name, phase: .calibration, underlying: error)
    }

    var samples: [Sample] = []
    samples.reserveCapacity(policy.iterations.maxIterations + 2)
    while policy.iterations.shouldContinue(after: samples) {
      let iteration = samples.count
      let phase = BenchmarkPhase.measurement(iteration: iteration)
      let context = executionContext(step: step, suite: suite, phase: phase)
      await record(
        kind: .iterationStarted,
        context: Benchmark.Event.Context(step: step, iteration: iteration, phase: phase),
        eventRecorders: eventRecorders
      )
      await notifyWillRun(context: context, observers: observers)
      let sample: Sample
      do {
        sample = try await measureSample(workload, iteration: iteration, batchSize: batchSize)
      } catch {
        await notifyDidFail(context: context, error: error, observers: observers)
        await recordIssue(
          error, step: step, iteration: iteration, phase: phase, eventRecorders: eventRecorders)
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name,
          case: step.benchmarkCase.name,
          phase: phase,
          underlying: error
        )
      }
      samples.append(sample)
      await record(
        kind: .sampleRecorded,
        context: Benchmark.Event.Context(
          step: step, iteration: iteration, phase: phase, sample: sample),
        eventRecorders: eventRecorders
      )
      await notifyDidRun(context: context, sample: sample, observers: observers)
      await record(
        kind: .iterationEnded,
        context: Benchmark.Event.Context(step: step, iteration: iteration, phase: phase),
        eventRecorders: eventRecorders
      )
    }

    if countsAllocations {
      let counts: RuntimeCounters.Counts?
      do {
        counts = try await RuntimeCounters.counting {
          try await workload.callRepeatedly(batchSize)
        }
      } catch {
        await recordIssue(
          error, step: step, iteration: nil, phase: .counting, eventRecorders: eventRecorders)
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name, case: step.benchmarkCase.name, phase: .counting, underlying: error)
      }
      if let counts {
        let calls = Double(batchSize)
        let sample = Sample(
          iteration: samples.count,
          batchSize: batchSize,
          values: [
            .allocations: Double(counts.allocations) / calls,
            .allocatedBytes: Double(counts.allocatedBytes) / calls,
            .retains: Double(counts.retains) / calls,
            .releases: Double(counts.releases) / calls,
          ]
        )
        samples.append(sample)
        await record(
          kind: .sampleRecorded,
          context: Benchmark.Event.Context(
            step: step, iteration: sample.iteration, phase: .counting, sample: sample),
          eventRecorders: eventRecorders
        )
      }
    }

    if recordsPeakMemory, let peak = PhysicalFootprint.peak() {
      let sample = Sample(iteration: samples.count, values: [.peakMemory: Double(peak)])
      samples.append(sample)
      await record(
        kind: .sampleRecorded,
        context: Benchmark.Event.Context(step: step, iteration: sample.iteration, sample: sample),
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

  /// Measures one timed sample of `batchSize` calls: wall-clock time, CPU
  /// time and any values the workload records, each divided by the batch size.
  private func measureSample(
    _ workload: BenchmarkWorkload,
    iteration: Int,
    batchSize: Int
  ) async throws -> Sample {
    let recorder = CustomMetricRecorder()
    let cpuStart = cpuClock?.now()
    let interval = try await CustomMetricRecorder.$current.withValue(recorder) {
      try await workload.callTimed(batchSize, clock: clock)
    }
    let cpuEnd = cpuClock?.now()
    let calls = Double(batchSize)
    var values: [Benchmark.Metric: Double] = recorder.values().mapValues { $0 / calls }
    values[.wallClock] = Double(interval.start.duration(to: interval.end)) / calls
    if let cpuStart, let cpuEnd {
      values[.cpuTime] = Double(cpuStart.duration(to: cpuEnd)) / calls
    }
    return Sample(iteration: iteration, batchSize: batchSize, values: values)
  }

  /// Chooses how many calls each sample measures. Automatic batching grows
  /// the batch until one batch lasts the target duration; the timed batches
  /// it runs are not recorded.
  private func calibratedBatchSize(
    _ workload: BenchmarkWorkload,
    policy: BatchingPolicy,
    lastWarmupNanoseconds: UInt64?
  ) async throws -> Int {
    switch policy {
    case .fixed(let count):
      return count
    case .automatic(let targetNanoseconds, let maxBatchSize):
      if let lastWarmupNanoseconds, lastWarmupNanoseconds >= targetNanoseconds {
        return 1
      }
      var count = 1
      while count < maxBatchSize {
        let interval = try await workload.callTimed(count, clock: clock)
        let elapsed = interval.start.duration(to: interval.end)
        if elapsed >= targetNanoseconds {
          break
        }
        let estimate =
          elapsed == 0
          ? count * 100
          : Int((Double(count) * Double(targetNanoseconds) / Double(elapsed)).rounded(.up))
        count = min(maxBatchSize, max(count * 2, min(estimate, count * 100)))
      }
      return count
    }
  }

  private func executionContext(
    step: Plan.Step,
    suite: BenchmarkSuite,
    phase: BenchmarkPhase
  ) -> BenchmarkExecutionContext {
    BenchmarkExecutionContext(
      suiteName: suite.name,
      caseName: step.benchmarkCase.name,
      size: step.size,
      arguments: step.arguments,
      phase: phase
    )
  }

  private func recordIssue(
    _ error: any Error,
    step: Plan.Step,
    iteration: Int?,
    phase: BenchmarkPhase,
    eventRecorders: [any BenchmarkEventRecorder]
  ) async {
    await record(
      kind: .issueRecorded,
      context: Benchmark.Event.Context(
        step: step, iteration: iteration, phase: phase, message: String(describing: error)),
      eventRecorders: eventRecorders
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
    sample: Sample?,
    observers: [any BenchmarkExecutionObserver]
  ) async {
    for observer in observers {
      await observer.benchmarkDidRun(context: context, sample: sample)
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
