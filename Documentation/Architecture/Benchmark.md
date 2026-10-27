# Benchmark Architecture

## Scope / Purpose

This document is the current architecture source of truth for the Benchmark
product domain of `swift-benchmark`.

Benchmark is repeatable workload measurement for test, benchmark, and CI
workflows. It owns benchmark declaration, discovery, planning, execution,
warmup, batching, iterations, samples and their metrics,
`Benchmark.Measurement` rows, Swift Testing-style benchmark arguments,
`Benchmark.Scale` curve keys, and structured results.

Benchmark is not production runtime instrumentation. It must remain separate
from Instruments:

```text
Instruments
  -> runtime-safe observability
  -> spans, events, recorders, timelines, Signpost backend

Benchmark
  -> repeated measurement runner
  -> test / benchmark / CI execution harness
```

Benchmark exposes execution hooks that Report can combine with optional
Instruments timelines, but Benchmark must not be defined as Signpost, tracing,
spans, or runtime instrumentation. `Metrics.md` owns what a sample measures.

## Current Structure

The Benchmark target holds the declaration macros' public declarations,
discovery, runner plans, suite/case declarations, configuration, the runner,
batch calibration, the metric collectors (CPU clock, memory footprint, Swift
runtime counters, custom metric recording), the measurement gate, samples,
argument/scale rows, structured results, the event stream, and `blackHole`.
The declaration macros are implemented in `BenchmarkMacro`.

Benchmark core does not depend on Instruments, Report, Testing, or XCTest.
Report, the testing adapters, the CLI and the command plugin build on its
public API.

## Source Authority

Benchmark absorbs mature Apple/Swift designs without making unrelated topology
local architecture truth. Architecture documents may cite trusted Apple/Swift
alignment sources when the concept maps cleanly to the local framework;
non-official evidence is not architecture truth.

## Core Model

- `BenchmarkSuite`: advanced representation of a named collection of
  benchmark cases, and the lowering target of `@BenchmarkSuite`.
- `BenchmarkCase`: advanced representation of one repeatable workload
  declaration, and the lowering target of `@Benchmark`.
- `_BenchmarkDiscovery`: the discovery substrate macro-generated and bridged
  discovery types conform to.
- `BenchmarkDiscovery`: materialized suite/case discovery result for tooling
  and package workflows.
- `BenchmarkRunner`: executes plans and produces structured results.
- `BenchmarkRunner.Plan`, `.Step`, `.Action` and `.Filter`: the filtered,
  configured, validated executable graph; one step per case, argument row or
  Dimension size; what to do for a step (measure, skip, or record a planning
  failure); and suite/case/tag selection. Each step has an identifier built
  from its suite name, case name and row, with punctuation percent-encoded, so
  distinct names give distinct identifiers. An argument row is identified by
  its values' descriptions, which keeps the identifier the same in every
  process, whatever order a collection lists its elements in. The package
  workflow selects a step by this identifier in each host process.
- `BenchmarkConfiguration`: warmup, iteration and batching policies for a suite
  or case.
- `WarmupPolicy`, `IterationPolicy` and `BatchingPolicy`.
- `BenchmarkClock`: timing abstraction used by the runner and tests;
  `ContinuousBenchmarkClock` is the default and `ProcessCPUClock` reads CPU
  time.
- `Benchmark.Metric` and `Sample`: a metric descriptor, and one sample's
  per-call values.
- `Benchmark.ArgumentValue` / `Benchmark.ArgumentRow`: row metadata for
  parameterized declarations.
- `Benchmark.Dimension`: metadata for native `.dimension(sizes:)` declarations.
- `Benchmark.Scale`: Apple-aligned `Int` wrapper for the numeric curve key of
  a row.
- `Measurement` and `Measurement.Row`: measured rows and samples for a case.
- `BenchmarkResult`: structured output for a benchmark case.
- `Benchmark.Event` and `Benchmark.Event.Stream`: lifecycle events and their
  records.
- `blackHole`: anti-optimization utility for benchmark workloads.

## Apple-Aligned Discovery / Plan / Runner Skeleton

Swift Testing is the primary architecture system for Benchmark declaration,
discovery, planning, filtering, trait/scoping, source-location, and runner
shape. Benchmark follows one-to-one design and naming alignment for valuable
Swift Testing concepts, then adds benchmark-specific semantics on top:

```text
Swift Testing:
@Suite / @Test
  -> _TestDiscovery
  -> Test.all
  -> Runner.Plan
  -> Runner
  -> Issue / Attachment / Event

swift-benchmark:
@BenchmarkSuite / @Benchmark
  -> _BenchmarkDiscovery
  -> BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event.Stream / BenchmarkResult
```

Deviations are justified by benchmark semantics such as measurement, samples,
metrics, baselines, or portability. This is design alignment, not copying of
implementation internals.

Accepted naming:

- `@BenchmarkSuite` / `@Benchmark` mirror `@Suite` / `@Test`.
- `_BenchmarkDiscovery` mirrors the role of `_TestDiscovery`.
- `BenchmarkRunner.Plan`, `.Step` and `.Action` mirror `Runner.Plan`,
  `Runner.Plan.Step` and `Runner.Plan.Action`.
- `BenchmarkTrait`, `BenchmarkSuiteTrait`, `BenchmarkCaseTrait`, and
  `BenchmarkScoping` mirror Swift Testing's `Trait`, `SuiteTrait`, `TestTrait`,
  and `TestScoping`.
- `arguments:` follows Swift Testing parameterization semantics for one
  collection, two-collection Cartesian products, and zipped pairs.
- `.dimension(sizes:)` is the native spelling for scale rows; it lowers to
  `Benchmark.Scale` rows.

Rejected implementation coupling:

- Do not copy Swift Testing's `_TestDiscovery` ABI records, section scanning,
  legacy discovery modes, environment toggles, or event-stream ABI.
- Do not make Benchmark core depend on the `Testing` module.
- Do not make Swift Testing `Issue` or `Attachment` the benchmark result truth.
- Do not use `Provider` / `Probe` as package workflow vocabulary.

Benchmark-specific strengthening that Swift Testing does not provide: warmup,
batching, measured iterations, fixed and adaptive policies, samples of several
metrics, `Benchmark.Measurement` rows, argument rows with numeric scale curves,
and the event records Report builds from.

## Workload Model

`BenchmarkCase` stores each row's workload as synchronous or asynchronous.
Synchronous, throwing, async and async throwing authoring overloads wrap the
declared function; synchronous workloads are timed in a loop without suspension
points. Non-`Void` workload overloads route returned values through
`blackHole`. A row's input, its argument values or the Dimension `input:`
for its size, is made once when the row's workload is made, before warmup, and
is not measured.

A workload with per-call setup, declared with `setup:` on `@Benchmark` or the
`Benchmark` initializers, takes a fresh input on every call. Before each
measured batch, whether warmup, calibration, a timed sample or the counting
pass, the runner makes one input per call into a buffer; the calls take the
inputs `inout` by index, and the buffer is released after the batch's clocks
and counters are read. Setup and freeing the inputs are therefore neither
timed nor counted. Per-call setup is available for plain and Dimension
benchmarks; Swift Testing bridge benchmarks take no inputs.

## Runner

A declaration API alone is not Benchmark. The runner executes workloads
repeatedly and produces structured results:

```swift
BenchmarkRunner(clock:cpuClock:countsProcessEvents:countsAllocations:recordsPeakMemory:)
  .run(_ plan: BenchmarkRunner.Plan, observers:eventRecorders:) async throws -> [BenchmarkResult]
```

For each measuring step the runner validates the configuration, makes the
workload, runs warmup calls, calibrates the batch size, records one timed sample
per measured iteration, then a counting sample and, when enabled, a peak memory
sample (see `Metrics.md`). A host process the CLI starts for timing skips the
counting sample; one it starts for counting records only the counting sample,
after a first counting pass that warms what counting allocates once. Steps run
serially, and a process-wide measurement gate keeps steps of concurrent runners
from overlapping. Thrown errors are preserved with suite, case and phase context
and never become samples. Skips and planning failures are explicit plan actions.

Default policies: warmup `.iterations(1)`, measured iterations
`.iterations(10)`, and automatic batching with a 1 ms target. Warmup counts must
be nonnegative, iteration counts positive, and batch sizes positive.
`IterationPolicy.adaptive` stops between a minimum and maximum iteration count
once a minimum duration is reached or a maximum duration would be exceeded,
counting each batch's whole duration.

## Result And Measurement Model

Raw `Sample` values are the source of truth for measured work.
`Benchmark.Measurement` preserves rows and samples so Report, baseline and
regression workflows can recompute or compare derived facts:

- `Measurement.Row(samples:)` for ordinary benchmarks, with `size == nil`;
- one row per argument value, with argument metadata and a `Benchmark.Scale`
  when the argument is an integer or integer-backed;
- one row per Dimension size.

Statistics belong to `Report.Measurement.Row`, not Benchmark measurement truth.
`BenchmarkResult` includes suite and case identity, tags, source location,
effective configuration and measurement. Export formats, baseline storage,
comparison policy and CI gates are Report and CLI concerns.

## Authoring Model

The primary authoring experience is macro-first and matches Swift Testing's
`@Suite` / `@Test` mental model:

```swift
import Benchmark

@BenchmarkSuite(
  "Parser",
  .tag("parser"),
  .configuration(.init(warmup: .iterations(2), iterations: .iterations(20)))
)
struct ParserBenchmarks {
  @Benchmark("Parse document")
  func parseDocument() throws {
    try blackHole(parser.parse(input))
  }

  @Benchmark("Parse by size", arguments: [10, 100, 1_000])
  func parseBySize(_ byteCount: Int) throws {
    try blackHole(parser.parse(makeInput(byteCount: byteCount)))
  }

  @Benchmark("Parse sized", .dimension(sizes: [10, 100]))
  func parseSized(size: Benchmark.Scale) throws {
    try blackHole(parser.parse(makeInput(byteCount: size.rawValue)))
  }
}
```

`BenchmarkSuite`, `BenchmarkCase`, the `Benchmark(...)` initializers and the
result builder remain the lowering and execution model for generated metadata,
tools, adapters, fixtures and advanced programmatic use; they are not the
ordinary user's first mental model.

Authoring rules:

- `@BenchmarkSuite` accepts suite-level `BenchmarkSuiteTrait` values and
  `@Benchmark` case-level `BenchmarkCaseTrait` values.
- Suite-level traits are inherited or scoped into child cases during plan
  construction, following the Swift Testing trait model; a case's own
  configuration overrides its traits', which override the suite's.
- A global `benchmark("Name") { ... }` function is a non-goal.
- Benchmark core must not depend on Swift Testing.
- Instruments macros are not benchmark declarations, and benchmark
  declaration macros do not insert `#span`, `@Span`, `@Instrumented`, or
  `@InstrumentedMembers`.
- Source locations are captured at the user declaration.

## Dimension

Dimension is the Benchmark-native input-size model. `Benchmark.Scale` is an
Apple-aligned `Int` wrapper. The `.dimension(sizes:)` trait on a method that
takes a `Benchmark.Scale`, or the programmatic
`Benchmark(_:dimension:input:_:)` initializer, produces one step and one
`Benchmark.Measurement.Row` per size; the input is made once per size, outside
measured iterations. The architecture is single-Dimension; multi-Dimension
analysis is proposal scope (`../Proposals/FutureMultiDimensionMeasurement.md`).

## Package Workflow And Discovery

The package workflow is declaration-driven `swift package benchmark` with
`list`, `run`, `check`, `trace`, `baseline write/update/check`, `diff` and
`render`. Code declarations are the source of truth; users maintain no
manifest, naming convention or provider boilerplate for discovery.

```text
Benchmark declarations
  -> _BenchmarkDiscovery records (macro-generated or bridged)
  -> BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner, one host process per step
  -> Benchmark.Event.Stream records
  -> ReportDocument
```

The package command must enter user code to obtain executable closures, so it
runs a host: generated by the command plugin for library and test targets, or
an executable passed with `--host`. The host is an implementation bridge, not a
user-facing Benchmark concept.

Discovery and planning rules:

- discovery parses sources with SwiftSyntax; it does not rely on directory
  layout or target naming conventions,
- do not expose hand-written provider APIs or global mutable registration,
- build a `BenchmarkRunner.Plan` before execution,
- make skip and planning-failure states explicit in plan actions,
- do not copy Swift Testing `_TestDiscovery` internals or unrelated
  baseline/result/export formats.

## Official Alignment Rules

- Directly absorb `blackHole` and keep unsafe/compiler-sensitive details
  isolated inside Benchmark.
- Adapt `swiftlang/swift-testing` declaration, discovery, trait/scoping,
  filter, plan and runner shape; keep the skeleton and naming, reject runtime
  dependency and internal discovery/ABI details.
- Adapt `swift-collections-benchmark` input-size, per-size measurement,
  amortized and comparison semantics into `Benchmark.Dimension`,
  `Benchmark.Measurement`, `Report.Measurement` and `Report.DimensionCurve`,
  with Swift-Testing-style traits and plan expansion as the user experience.
- Adapt `swiftlang/swift` benchmark suite organization, environment metadata,
  sample preservation and current-vs-baseline discipline without inheriting
  compiler build-system assumptions.
- Keep allocation counting in a separate counting pass so that hooks never slow
  the timed samples.
- Use XCTest performance APIs as adapter vocabulary only.

## Swift Testing Boundary

Benchmark core must not depend on Swift Testing:

```text
Benchmark core
  <- Swift Testing adapter
  <- XCTest adapter
  <- CLI / plugin
```

Swift Testing suites and tests enroll with the BenchmarkTesting trait:

```swift
import Benchmark
import BenchmarkTesting
import Testing

@Suite(.benchmark(configuration: .init(warmup: .iterations(2), iterations: .iterations(20))))
struct ParserPerformanceTests {
  @Test func parseSmallDocument() throws {
    try blackHole(parser.parse(smallInput))
  }

  @Test(.benchmark(configuration: .init(iterations: .iterations(50))), arguments: [10, 100])
  func parseLargeDocument(byteCount: Int) throws {
    try blackHole(parser.parse(makeInput(byteCount: byteCount)))
  }
}
```

`swift test` runs these tests once as tests. The package workflow bridges
enrolled declarations into generated `_BenchmarkDiscovery` records and measures
them with the Benchmark runner:

```text
@Suite(.benchmark...) / @Test(.benchmark...)
  -> BenchmarkTesting discovery bridge
  -> generated _BenchmarkDiscovery
  -> BenchmarkRunner.Plan / BenchmarkRunner
  -> ReportDocument
```

Adapter rules:

- Swift Testing depends on Benchmark core; Benchmark core does not depend on
  Swift Testing.
- `@Suite(.benchmark...)` enrolls contained and nested tests; `@Test(.benchmark...)`
  enrolls one test and refines suite configuration.
- Testing traits do not replace the core runner, sample model,
  `Benchmark.Measurement` or structured results.
- `swift package benchmark` is the primary benchmark command; the Swift
  Testing and XCTest adapters measure in process and project `ReportDocument`
  verdicts into their native issues and attachments.

## Report Boundary

Benchmark produces structured results and event records. Report structures,
compares, attributes, renders summaries and exports them; baselines, budgets,
warnings and CI gates belong to Report, the CLI and the adapters, never to the
runner.

## Optional Relationship With Instruments

```text
Benchmark runner
  -> execution observer around each measured call
  -> Instruments recorder captures spans/events into a timeline
  -> Report correlates the timeline with the sample
```

This path is optional and does not make Benchmark an instrumentation, tracing,
Signpost, or span system. Timeline correlation binds each measured sample to
the spans and events of its iteration, so a report can attribute a slow sample
to phases such as `Tokenize` or `ParseAST`. `SignpostRecorder` and
`os_signpost` remain Apple backend plumbing inside Instruments.

## Risks / Ongoing Extension Points

- Swift counting metrics depend on the Swift runtime's instrumentation hooks
  on Apple platforms and on the interposer library in a counting process on
  Linux; heap metrics need the interposer on both (see `Metrics.md`).
- Presentation templates may grow, but they remain Report or tool artifacts
  over the structured report model.

## Related Documents

- `ProductDomains.md`
- `Metrics.md`
- `Instruments.md`
- `Report.md`
