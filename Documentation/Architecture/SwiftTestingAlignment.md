# Swift Testing Alignment

## Scope / Purpose

This document owns the Swift-Testing-aligned architecture strategy. It
explains which Apple design ideas are primary architecture inputs, which names
and shapes should align, and where benchmark-specific extensions begin.

This is the highest-level design rule for Benchmark:

```text
Benchmark is a Swift-Testing-style performance specialization.
```

Swift Testing provides the primary architecture system for declaration,
discovery, traits, scoping, filtering, source locations, runner plans, runner
execution, events, recorders, issues, and attachments. Benchmark extends that
system for performance measurement.

## Current Implementation Status

Current source implements the Swift-Testing-shaped Benchmark skeleton:
`@BenchmarkSuite` / `@Benchmark`, benchmark traits/tags/scoping,
`_BenchmarkDiscovery`, `BenchmarkDiscovery`, `BenchmarkRunner.Plan`,
`BenchmarkRunner`, `Benchmark.Event.Stream`, console/JSON Lines recorders, and
event-driven `ReportRecorder` / `ReportBuilder` construction. Swift Testing
and XCTest remain adapter sinks over `ReportDocument`; Benchmark core does not
import their runtimes.

## Core Mapping

| Swift Testing | swift-benchmark |
| --- | --- |
| `@Suite` | `@BenchmarkSuite` |
| `@Test` | `@Benchmark` |
| `Trait` | `BenchmarkTrait` |
| `SuiteTrait` | `BenchmarkSuiteTrait` |
| `TestTrait` | `BenchmarkCaseTrait` |
| `TestScoping` | `BenchmarkScoping` |
| `_TestDiscovery` | `_BenchmarkDiscovery` |
| `Test.all` / discovery result | `BenchmarkDiscovery` |
| `Runner.Plan` | `BenchmarkRunner.Plan` |
| `Runner.Plan.Step` | `BenchmarkRunner.Plan.Step` |
| `Runner.Plan.Action` | `BenchmarkRunner.Plan.Action` |
| `Event` | `Benchmark.Event` |
| `Event.Kind` | `Benchmark.Event.Kind` |
| `Event.Context` | `Benchmark.Event.Context` |
| event stream | `Benchmark.Event.Stream` |
| console recorder | `Benchmark.Event.ConsoleOutputRecorder` |
| JSON event stream | `Benchmark.Event.JSONLinesRecorder` |
| `Issue` | adapter sink for `ReportDocument` verdicts |
| `Attachment` | adapter sink for Report attachments |

## Alignment Rules

- Default to Swift Testing naming and type shape when the concept has benchmark
  value.
- Prefer nested type style where it clarifies ownership, for example
  `Benchmark.Event.Kind` and `Benchmark.Event.Stream.Record`.
- Do not nest only for aesthetics. Product boundaries still matter.
- `ReportDocument` remains a Report product concept and should not be renamed
  only to mimic `Report.Document`.
- `BenchmarkSuite` and `BenchmarkCase` are internal/SPI or advanced lowering
  targets, not public-first authoring contracts.
- `@BenchmarkSuite` / `@Benchmark` are the native Benchmark declaration UX.
- `@Suite(.benchmark...)` / `@Test(.benchmark...)` are Swift Testing adapter UX.

## Benchmark Extensions

Benchmark adds capabilities Swift Testing does not provide:

- warmup,
- measured iterations,
- fixed/adaptive/min-duration/max-duration policy,
- raw samples,
- `Benchmark.Measurement` rows,
- `Benchmark.Dimension` input-size parameterization,
- `Report.Measurement` metrics and `Report.DimensionCurve`,
- memory/allocation diagnostics,
- timeline attribution,
- baseline/budget/diff/check,
- `ReportDocument` evidence,
- package benchmark workflow.

These additions extend the Swift Testing-shaped skeleton. They should not
replace it with unrelated topology.

## Rejected Coupling

- Do not depend on the Swift Testing runtime in Benchmark core.
- Do not copy `_TestDiscovery` internals, ABI event streams, legacy discovery
  modes, section scanning, or environment toggles as public contracts.
- Do not make Swift Testing `Issue` or `Attachment` the Benchmark or Report
  truth.
- Do not make Swift Testing JUnit XML, human output, or ABI event stream the
  Report truth.
- Do not introduce `BenchmarkTask` as the local core model.
- Do not expose global `benchmark("Name") { ... }` as the product entry point.

## Related Documents

- `BenchmarkDeclarations.md`
- `BenchmarkExecution.md`
- `ReportEvidence.md`
- `WorkflowAdapters.md`
