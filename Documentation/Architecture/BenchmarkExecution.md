# Benchmark Execution

## Scope / Purpose

This document owns the Benchmark execution architecture: plan construction,
runner behavior, measurement policy, samples, Measurement rows, and live event
stream.

It continues the Swift Testing-shaped pipeline:

```text
BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event.Stream
  -> ReportRecorder / ReportBuilder
```

## Current Implementation Status

Current source implements `BenchmarkRunner.Plan` with suite/case/tag filters,
effective trait/configuration calculation, Dimension expansion, measure/skip/
planning-failure actions, and deterministic ordering. `BenchmarkRunner`
supports fixed iterations by default plus opt-in adaptive, minimum-duration,
and maximum-duration policies. It emits `Benchmark.Event` records to console
and JSON Lines recorders while preserving the legacy observer bridge.
`ReportRecorder` and `ReportBuilder` consume the same event stream into
`ReportDocument`.

## Runner Plan

`BenchmarkRunner.Plan` is the executable boundary between declaration discovery
and measurement.

It owns:

- selected suites and cases,
- effective suite/case traits,
- filters,
- source locations,
- Dimension size expansion,
- effective runner configuration,
- skip actions,
- planning-failure actions,
- executable run actions.

`BenchmarkRunner.Plan.Step` and `BenchmarkRunner.Plan.Action` mirror Swift
Testing's `Runner.Plan.Step` and `Runner.Plan.Action` naming style while
carrying benchmark-specific measurement semantics.

## Runner Policies

The default runner policy is deterministic fixed measured iterations.

Implemented policies:

- fixed measured iterations by default,
- warmup before measurement,
- opt-in adaptive policy,
- opt-in `minDuration`,
- opt-in `maxDuration`,
- validation before workload execution,
- thrown workload failures remain errors and are not samples.

Warmup samples are not measured samples. Each measured iteration produces one
sample for the measured metric unless execution fails.

## Operation Model

Runner execution normalizes benchmark bodies into:

```swift
@Sendable () async throws -> Void
```

Sync, throwing, async, and async throwing user declarations lower into this
shape. Non-`Void` returns should pass through `blackHole` when exposed by a
public authoring surface.

## Samples And Measurement

Raw samples are the source of truth for measurement.

`Benchmark.Measurement` is the only benchmark measurement truth. It represents
rows and samples:

- ordinary benchmarks produce one `Measurement.Row(size: nil, samples: ...)`,
- Dimension benchmarks produce one row per `Benchmark.Scale`,
- the Dimension generator runs before measured iterations and is not sampled.

Each sample records the per-call value of every metric the step measured;
`Metrics.md` owns which metrics those are and how they are measured. Report
projects measurement rows into `Report.Measurement`, with per-metric
statistics on each row. Baseline, budget, diff, and renderer code must not
compute independent facts from display strings.

## Live Event Stream

Benchmark execution emits Swift-Testing-style nested events:

- `Benchmark.Event`
- `Benchmark.Event.Kind`
- `Benchmark.Event.Context`
- `Benchmark.Event.Stream`
- `Benchmark.Event.Stream.Record`
- `Benchmark.Event.InMemoryRecorder`
- `Benchmark.Event.ConsoleRecorder`
- `Benchmark.Event.JSONLinesRecorder`

The stream is a live observation and tooling protocol, and the input Report
builds documents from. Records are `Codable`, so a host process can hand them to
the CLI.

`ReportDocument` remains the durable, diffable, CI-stable snapshot truth.

## Event Kinds

Implemented event coverage:

- plan started/ended around the run's steps,
- case started/ended, and skipped,
- Dimension or argument row started/ended,
- warmup started/ended,
- iteration started/ended,
- sample recorded, for timed, counting and peak memory samples,
- issue recorded, for planning and execution failures.

## Acceptance Checks

- Plan construction tests for filters, traits, Dimension expansion, skips, and
  planning failures.
- Runner policy tests for fixed/adaptive/min/max behavior.
- Workload error tests.
- Clock, sample, and measurement row tests.
- `Benchmark.Event.Stream` JSON Lines fixture tests.
- Event-to-`ReportDocument` construction tests.
