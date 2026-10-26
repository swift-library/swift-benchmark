// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension BenchmarkRunner {
  func runRow(
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

    let footprintAtStart = recordsPeakMemory ? PhysicalFootprint.read() : nil
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
        lastWarmupNanoseconds = try await workload.callTimed(1, clock: clock).nanoseconds
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
    if countsOnly {
      // A first pass through the counting path warms what it allocates once,
      // such as the task allocator's memory for its calls.
      do {
        _ = try await countAllocations(workload, batchSize: batchSize)
      } catch {
        await recordIssue(
          error, step: step, iteration: nil, phase: .counting, eventRecorders: eventRecorders)
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name, case: step.benchmarkCase.name, phase: .counting, underlying: error)
      }
    }
    while !countsOnly, policy.iterations.shouldContinue(after: samples) {
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

    if countsAllocations || countsOnly {
      let values: [Benchmark.Metric: Double]
      do {
        values = try await countAllocations(workload, batchSize: batchSize)
      } catch {
        await recordIssue(
          error, step: step, iteration: nil, phase: .counting, eventRecorders: eventRecorders)
        throw BenchmarkRunnerError.caseFailed(
          suite: suite.name, case: step.benchmarkCase.name, phase: .counting, underlying: error)
      }
      if !values.isEmpty {
        let sample = Sample(iteration: samples.count, batchSize: batchSize, values: values)
        samples.append(sample)
        await record(
          kind: .sampleRecorded,
          context: Benchmark.Event.Context(
            step: step, iteration: sample.iteration, phase: .counting, sample: sample),
          eventRecorders: eventRecorders
        )
      }
    }

    if !countsOnly, let start = footprintAtStart, let end = PhysicalFootprint.read(),
      end.peak > start.peak
    {
      let sample = Sample(
        iteration: samples.count, values: [.peakMemory: Double(end.peak - start.current)])
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
  /// time, process counters and any values the workload records, each divided
  /// by the batch size.
  private func measureSample(
    _ workload: BenchmarkWorkload,
    iteration: Int,
    batchSize: Int
  ) async throws -> Sample {
    let recorder = CustomMetricRecorder()
    let interval = try await CustomMetricRecorder.$current.withValue(recorder) {
      try await workload.callTimed(
        batchSize, clock: clock, cpuClock: cpuClock, countsProcessEvents: countsProcessEvents)
    }
    let calls = Double(batchSize)
    var values: [Benchmark.Metric: Double] = recorder.values().mapValues { $0 / calls }
    for (metric, total) in interval.counters {
      values[metric] = total / calls
    }
    values[.wallClock] = Double(interval.nanoseconds) / calls
    if let cpuNanoseconds = interval.cpuNanoseconds {
      values[.cpuTime] = Double(cpuNanoseconds) / calls
    }
    return Sample(iteration: iteration, batchSize: batchSize, values: values)
  }

  /// Counts one batch of `batchSize` calls: Swift runtime allocations and
  /// reference counting, and heap allocations where the interposer library is
  /// loaded, each divided by the batch size. Empty where nothing counts.
  private func countAllocations(
    _ workload: BenchmarkWorkload,
    batchSize: Int
  ) async throws -> [Benchmark.Metric: Double] {
    let interposer = InterposerCounters.loaded
    interposer?.start()
    let hooked: RuntimeCounters.Counts?
    do {
      hooked = try await RuntimeCounters.counting {
        try await workload.callRepeatedly(batchSize)
      }
    } catch {
      interposer?.stop()
      throw error
    }
    interposer?.stop()
    let interposed = interposer?.counts()

    let calls = Double(batchSize)
    var values: [Benchmark.Metric: Double] = [:]
    if let runtime = hooked ?? interposed?.runtime {
      values[.swiftAllocations] = Double(runtime.allocations) / calls
      values[.swiftAllocatedBytes] = Double(runtime.allocatedBytes) / calls
      values[.swiftRetains] = Double(runtime.retains) / calls
      values[.swiftReleases] = Double(runtime.releases) / calls
    }
    if let interposed {
      values[.heapAllocations] = Double(interposed.heapAllocations) / calls
      values[.heapAllocatedBytes] = Double(interposed.heapAllocatedBytes) / calls
      values[.heapNetAllocations] =
        (Double(interposed.heapAllocations) - Double(interposed.heapFrees)) / calls
    }
    return values
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
        let elapsed = try await workload.callTimed(count, clock: clock).nanoseconds
        if elapsed >= targetNanoseconds {
          break
        }
        // Grow at least twofold and at most a hundredfold per round, aiming at
        // the count that reaches the target. Computed in Double and clamped to
        // the maximum before conversion, so large targets cannot overflow.
        let current = Double(count)
        let estimate =
          elapsed == 0
          ? current * 100 : (current * Double(targetNanoseconds) / Double(elapsed)).rounded(.up)
        let next = min(Double(maxBatchSize), max(current * 2, min(estimate, current * 100)))
        count = Int(next)
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
      rowID: step.argumentRow?.id,
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

  func record(
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
