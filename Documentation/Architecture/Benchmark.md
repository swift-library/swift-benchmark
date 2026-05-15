# Benchmark Architecture

## Scope / Purpose

This document is the current architecture source of truth for the Benchmark
product domain of `swift-benchmark`.

Benchmark is repeatable workload measurement for test, benchmark, and CI
workflows. It owns benchmark declaration, execution, warmup, iterations,
samples, `Benchmark.Measurement` rows, Swift Testing-style benchmark
arguments, `Benchmark.Scale` curve keys, and structured results.

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
spans, or runtime instrumentation.

This document describes the implemented Benchmark product architecture and the
accepted workflow boundaries for the current scope. Future
extensions are tracked as extension points rather than current implementation
defects.

## Current Structure

Benchmark core is implemented in this repository.

Current package products include `Instruments`, `Benchmark`, `Report`,
`Memory`, `BenchmarkTesting`, and `BenchmarkXCTest`. The Benchmark source tree
includes macro declarations, discovery, runner plans, suite/case declarations,
configuration, a serial async throwing runner, warmup, measured iterations,
samples, argument/scale rows, structured results, and `blackHole`.

Executable/plugin products include `swift-benchmark-cli`, `BenchmarkCLI`,
and `BenchmarkPlugin`. These extend Benchmark through Report-facing product
boundaries; Benchmark core does not depend on Instruments, Report, Testing,
XCTest, input-size presentation helpers, or Memory internals.

This architecture is the accepted documentation for the Benchmark direction.
Temporary execution notes are not architecture truth; completed implementation
facts should be absorbed into architecture documents and README.

Current source implements the declaration, discovery, trait/tag/scoping, plan,
runner, event stream, arguments/scale, and result model. It includes macro trait
lowering, adaptive/min/max runner policies, package host generation for
library targets, Report event collection, and adapter/report projection
over the same `ReportDocument` truth.

## Source Authority

Benchmark should absorb mature Apple/Swift designs without making unrelated
topology local architecture truth.

Architecture documents may cite trusted Apple/Swift alignment sources when the
concept maps cleanly to the local framework. Non-official evidence is not
architecture truth.

## Core Model

The target Benchmark core model is:

- `BenchmarkSuite`: internal/SPI or advanced representation of a named
  collection of benchmark cases.
- `BenchmarkCase`: internal/SPI or advanced representation of one repeatable
  workload declaration.
- `_BenchmarkDiscovery`: internal/SPI discovery substrate for macro-generated
  benchmark records.
- `BenchmarkDiscovery`: materialized suite/case discovery result for tooling
  and package workflows.
- `BenchmarkRunner`: executes suites/cases and produces structured results.
- `BenchmarkRunner.Plan`: filtered, configured, validated executable graph
  owned by the runner.
- `BenchmarkRunner.Plan.Step`: one executable suite/case planning step.
- `BenchmarkRunner.Plan.Action`: what the runner should do for a step, such as
  run, skip, or record a planning failure.
- `BenchmarkConfiguration`: per-suite or per-case execution settings.
- `WarmupPolicy`: how warmup work is run before measurement.
- `IterationPolicy`: how measured iterations are selected.
- `BenchmarkClock`: monotonic timing abstraction used by the runner and tests.
- `Sample`: one measured sample.
- `Benchmark.ArgumentValue` / `Benchmark.ArgumentRow`: row metadata for
  parameterized benchmark declarations.
- `Benchmark.Dimension`: compatibility metadata for native `.dimension(sizes:)`
  declarations.
- `Benchmark.Scale`: Apple-aligned `Int` wrapper for the optional numeric
  curve key inferred from benchmark arguments.
- `Measurement`: raw measured rows and samples for a case.
- `Measurement.Row`: optional scale, arguments, and measured samples.
- `BenchmarkResult`: structured output for a benchmark case.
- `blackHole`: anti-optimization utility for benchmark workloads.

These concepts define the architecture boundary and macro lowering target.
They do not all need to be public-first user authoring APIs.

## Apple-Aligned Discovery / Plan / Runner Skeleton

Swift Testing is the primary architecture system for Benchmark declaration,
discovery, planning, filtering, trait/scoping, source-location, and runner
shape. Benchmark should default to one-to-one design and naming alignment for
valuable Swift Testing concepts, then add benchmark-specific semantics as
extensions on top of that skeleton.

Benchmark discovery and execution should therefore follow the same
architectural shape as Swift Testing:

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
  -> ReportDocument / adapter sinks
```

The goal is one-to-one architectural alignment of the declaration, discovery,
plan, and runner skeleton whenever the Swift Testing concept has benchmark
value. Deviations must be justified by benchmark semantics such as measurement,
samples, baselines, diagnostics, or portability. This is design alignment, not
one-to-one copying of implementation internals.

Accepted naming:

- `@BenchmarkSuite` / `@Benchmark` mirror `@Suite` / `@Test`.
- `_BenchmarkDiscovery` mirrors the role of `_TestDiscovery` as an internal
  discovery substrate.
- `BenchmarkDiscovery` is the public/tooling-facing materialized discovery
  result.
- `BenchmarkRunner.Plan`, `BenchmarkRunner.Plan.Step`, and
  `BenchmarkRunner.Plan.Action` mirror `Runner.Plan`, `Runner.Plan.Step`, and
  `Runner.Plan.Action`.
- `BenchmarkTrait`, `BenchmarkSuiteTrait`, `BenchmarkCaseTrait`, and
  `BenchmarkScoping` mirror Swift Testing's `Trait`, `SuiteTrait`,
  `TestTrait`, and `TestScoping` if benchmark traits are introduced.
- `arguments:` follows Swift Testing parameterization semantics for one
  collection, two-collection Cartesian products, and zipped pairs.
- `.dimension(sizes:)` remains a native compatibility spelling that lowers to
  `Benchmark.Scale` rows.
- `BenchmarkRunner.Plan.Filter` is the filter model for suite, case, and tag
  selection over stable plan identities.

Rejected implementation coupling:

- Do not copy Swift Testing's `_TestDiscovery` ABI records, section scanning,
  legacy discovery modes, environment toggles, or event-stream ABI as local
  public contracts.
- Do not make Benchmark core depend on the `Testing` module.
- Do not make Swift Testing `Issue` or `Attachment` the Benchmark result truth.
  Benchmark result truth remains `ReportDocument`.
- Do not keep `Provider` / `Probe` as the package workflow vocabulary.
  Discovery/plan/runner are the product concepts. Reserve probe-style naming
  for diagnostics such as timeline, memory, allocation, future MetricKit, or
  trace collection.

Benchmark-specific strengthening that Swift Testing does not provide:

- warmup and measured iterations,
- fixed/adaptive/min-duration/max-duration policies,
- raw samples and `Benchmark.Measurement` rows,
- baseline, budget, regression, and CI verdicts,
- argument rows, numeric scale curves, and amortized behavior,
- Memory/allocation diagnostics,
- Instruments timeline attribution,
- `xctrace` Report diagnostics and future MetricKit production diagnostics,
- stable `ReportDocument` JSON.

## Operation Model

`BenchmarkCase` stores executable workload operations in one normalized shape:

```swift
@Sendable () async throws -> Void
```

Public authoring should support sync, throwing, async, and async throwing
workloads by wrapping them into that normalized operation path. The runner calls
only the normalized operation.

Non-`Void` workload overloads should route returned values through `blackHole`
so benchmarked work cannot be optimized away. Manual `blackHole(...)` remains
valid for explicit control inside a benchmark body.

## Runner Requirement

A declaration API alone is not Benchmark. Benchmark requires a real runner that
repeatedly executes workloads and produces structured results.

The runner owns:

- warmup,
- iterations,
- measurement,
- sample collection,
- `Benchmark.Measurement` row construction,
- structured result production.

The runner API should be async and throwing:

```swift
BenchmarkRunner.run(...) async throws -> [BenchmarkResult]
```

Runner rules:

- default to deterministic, serial execution; parallel execution requires a
  future accepted architecture change,
- run warmup before measured iterations,
- do not record warmup as measured samples,
- collect exactly one `Sample` per measured iteration,
- validate configuration before executing workloads,
- preserve thrown errors with suite, case, and phase context,
- do not convert thrown workload failures into measured samples.

Default policies:

- `WarmupPolicy.none`,
- `WarmupPolicy.iterations(Int)`,
- `IterationPolicy.iterations(Int)`,
- default warmup: `.iterations(1)`,
- default measured iterations: `.iterations(10)`,
- warmup iteration count must be nonnegative,
- measured iteration count must be positive.

`BenchmarkClock` abstracts monotonic timing. The default clock should be backed
by `ContinuousClock`; tests should be able to inject a clock where useful.

## Result And Measurement Model

Raw `Sample` values are the source of truth for measured work.
`Benchmark.Measurement` is the only benchmark measurement truth. It preserves
rows and samples so later Report, baseline, and regression workflows can
recompute or compare derived facts.

The measurement model is:

- `Measurement.Row(size: nil, samples: ...)` for ordinary benchmarks,
- `Measurement.Row(size: Benchmark.Scale, samples: ...)` for each
  Dimension size,
- generator setup outside measured iterations,
- raw sample preservation for each row.

Derived metrics such as mean, median, p90, p95, and p99 belong to
`Report.Measurement.Row.metrics`, not Benchmark measurement truth.
`Report.Measurement.Metric` is the selector vocabulary for baseline, budget,
diff, and curve workflows.

`BenchmarkResult` should include at least suite identity, case identity,
effective configuration, and measurement. Export formats, baseline storage,
metric selectors, and CI gate policy are Report/Regression concerns, not runner
semantics.

`BenchmarkRunner.Plan` should be the executable boundary between discovery and
measurement. It is where discovery results, filters, traits, effective
configuration, Dimension inputs, and planning failures become explicit steps
before measurement begins.

## Correlated Performance Evidence

The target is a structured performance evidence graph. The
core runner measures wall-clock samples; Report correlates those samples with
baselines, budgets, timeline spans/events, diagnostics metrics, source
locations, and trace artifacts.

The model should be typed and scope-linked, not rendered by hand-built strings:

```text
Run
  -> Suite
    -> Case
      -> Iteration / Sample
        -> Span / Event
          -> DiagnosticMetric / Attachment
```

Required scope identities:

- run ID,
- suite ID,
- case ID,
- iteration ID,
- sample ID,
- span/event ID and parent span ID where available,
- metric ID,
- attachment ID.

These IDs let a Report answer both high-level and drill-down questions:

- current result and sample distribution,
- current-vs-baseline delta,
- baseline and budget verdicts,
- which iteration regressed,
- which span/event dominated that iteration,
- which diagnostics or trace artifacts explain the detail.

The direction is flamegraph/speedscope-compatible timeline attribution, not
hardcoded presentation rendering. The durable target is a structured
attribution model; stable JSON, console summaries, and profiler-compatible
records are consumers of that model. Markdown, HTML, CSV, JMH, Influx, HDR, or
other presentation/export breadth belongs in optional templates, tools, MCPs,
or agent-driven assets unless a future accepted architecture change explicitly
makes Swift-owned presentation rendering a product goal.

## Authoring Model

The primary user authoring experience is macro-first and should match Swift
Testing's `@Suite` / `@Test` mental model:

```swift
@BenchmarkSuite(.iterations(100), .baseline("parser-baseline.json"))
struct ParserBenchmarks {
  @Benchmark(.time(max: .milliseconds(30)), .dimension(sizes: [10, 100]) { size in makeInput(size) })
  func parseDocument(_ input: Document) throws {
    try parser.parse(input)
  }
}
```

`BenchmarkSuite`, `BenchmarkCase`, and `BenchmarkRunner` remain the lowering and
execution model for generated metadata, tools, adapters, fixtures, and advanced
programmatic use. They should not be the ordinary user's first mental model and
do not need to be stabilized as public-first authoring APIs.

Benchmark declaration macros are part of the target:

```swift
@BenchmarkSuite
struct ParserBenchmarks {
  @Benchmark("ParseDocument")
  func parseDocument() throws {
    try parser.parse(input)
  }
}
```

Authoring rules:

- `@BenchmarkSuite` and `@Benchmark` are the primary user-facing declaration
  UX.
- `BenchmarkCase` / `BenchmarkSuite` are internal/SPI or advanced model types
  and generated metadata targets.
- `BenchmarkCase` is the canonical stored workload type.
- A global `benchmark("Name") { ... }` function is not a target user-facing
  entry point.
- A public `Benchmark("Name") { ... }` factory/typealias is optional only as an
  advanced compatibility or fixture helper; it must not define product
  architecture or README-first usage.
- Result-builder DSL may remain as an internal/SPI or advanced fixture/tooling
  construction path, not as the primary non-macro user model.
- `@BenchmarkSuite` and `@Benchmark` are independent Benchmark declaration
  macros that lower to `BenchmarkSuite` and `BenchmarkCase` metadata.
- `@BenchmarkSuite` accepts suite-level `BenchmarkSuiteTrait` values.
- `@Benchmark` accepts case-level `BenchmarkCaseTrait` values.
- Suite-level traits are inherited or scoped into child benchmark cases during
  `BenchmarkRunner.Plan` construction, following the Swift Testing trait model.
- Case-level traits can override, refine, or add to suite-level traits according
  to each trait's merge policy.
- Global `benchmark("Name") { ... }` convenience is a non-goal.
- Benchmark core must not depend on Swift Testing.
- Instruments macros are not benchmark declarations.
- Benchmark declaration macros must not automatically insert `#span`,
  `@Span`, `@Instrumented`, or `@InstrumentedMembers`.
- Source-location capture belongs at the user declaration.

## Dimension Authoring

Dimension is the Benchmark-native input-size model:

```swift
@Benchmark(.dimension(sizes: [10, 100]) { size in makeInput(size) })
func parseDocument(_ input: Document) throws {
  try parser.parse(input)
}
```

`Benchmark.Scale` is an Apple-aligned `Int` wrapper. The generator is
called once per size before measured iterations. It creates input and is not
sampled. Discovery preserves Dimension metadata, `BenchmarkRunner.Plan` expands
sizes into executable steps, and the runner records one
`Benchmark.Measurement.Row` per size. Ordinary benchmarks record one row with
`size == nil`.

The implemented architecture is single-Dimension only. Multi-Dimension,
coordinate generators, rows-by-columns derived size, facets, and heatmap
analysis are documented as future proposal scope, not active Benchmark
architecture.

## Package Workflow And Discovery

The package workflow target is declaration-driven `swift package benchmark`.
The command should support:

- `list`,
- `run`,
- `check`,
- `baseline write/update`,
- `diff`,
- `trace`,
- suite/case filters,
- warmup and iteration overrides,
- runner policy overrides,
- baseline/budget flags,
- diagnostics flags,
- output paths,
- quiet/progress separation,
- documented exit codes.

Code declarations are the source of truth. Users should not maintain separate
manifest/config files, target naming conventions, or public provider boilerplate
for benchmark discovery.

The accepted entry model is:

```text
Benchmark declarations
  -> _BenchmarkDiscovery records
  -> BenchmarkDiscovery result
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> ReportDocument
```

The runnable host constraint is acceptable because the package command must
enter user code to obtain executable benchmark closures. The host may be an
executable host, a Swift Testing host, or another accepted implementation
bridge, but the host bridge is an implementation detail and not a user-facing
Benchmark product concept.

Discovery and planning rules:

- do not rely on directory layout or target naming conventions,
- do not make a benchmark target type a product-domain concept,
- do not expose hand-written provider APIs as the primary user workflow,
- do not expose `Provider` / `Probe` as package workflow concepts,
- do not use global mutable registration as architecture truth,
- build a `BenchmarkRunner.Plan` before execution,
- make skip/planning-failure states explicit in plan actions where needed,
- do not copy unrelated build-tool boilerplate,
- do not copy Swift Testing `_TestDiscovery` implementation internals,
- do not copy unrelated baseline/result/export formats.

## Official Alignment Rules

The architecture should take the mature parts of trusted Apple/Swift sources
while discarding coupling that does not fit this product boundary:

- Directly absorb `blackHole` and keep unsafe/compiler-sensitive details
  isolated inside Benchmark.
- Adapt `swiftlang/swift-testing` declaration, discovery, trait/scoping,
  filter, plan, runner, issue, and attachment architecture shape. Keep the
  skeleton and naming; reject runtime dependency and internal discovery/ABI
  details.
- Adapt `swift-collections-benchmark` input-size, per-size measurement,
  amortized, result persistence, and comparison semantics into
  `Benchmark.Dimension`, `Benchmark.Measurement`, `Report.Measurement`, and
  `Report.DimensionCurve`.
- The upper-level Dimension user experience should be Swift-Testing-style
  benchmark traits and runner-plan expansion, not a separate benchmark
  declaration topology.
- Do not introduce Apple `BenchmarkTask` as the local core model. Dimension
  metadata should annotate `BenchmarkCase` declarations through
  `Benchmark.Dimension.Trait`, and `BenchmarkRunner.Plan` should expand
  `Benchmark.Scale` values into executable steps.
- Adapt `swiftlang/swift` suite organization, environment metadata, sample
  preservation, and current-vs-baseline discipline without inheriting compiler
  build-system assumptions.
- Keep allocation/resource regression discipline in the Memory seam, not in the
  wall-clock runner core.
- Keep runner, CLI, report, baseline, budget, and provider/profiler
  capabilities expressed as local requirements and local concepts.
- Use XCTest performance APIs as adapter vocabulary only.

## Swift Testing Boundary

Benchmark core must not depend on Swift Testing.

Correct dependency direction:

```text
Benchmark core
  <- Swift Testing adapter
  <- XCTest adapter
  <- CLI / plugin
```

Swift Testing suites and traits are adapters over Benchmark core. Suite-level
and test-level benchmark traits are both part of the target UX:

```swift
@Suite(.benchmark(.iterations(100), .baseline("parser-baseline.json")))
struct ParserPerformanceTests {
  @Test
  func parseSmallDocument() throws {
    try parser.parse(smallInput)
  }

  @Test(.benchmark(.time(max: .milliseconds(30)), .dimension(sizes: [10, 100]) { size in makeInput(size) }))
  func parseLargeDocument() throws {
    try parser.parse(largeInput)
  }
}
```

`@Suite(.benchmark(...))` provides benchmark defaults, budgets, baselines,
diagnostics, scoping, and other suite-level context. `@Test(.benchmark(...))`
marks or refines an individual Testing test as a Benchmark/Report consumer.
Suite-level and test-level traits merge into the same `BenchmarkRunner.Plan` as
native `@BenchmarkSuite` / `@Benchmark` declarations.

Swift Testing adapter execution path:

```text
@Suite(.benchmark...) / @Test(.benchmark...)
  -> BenchmarkTesting discovery bridge or adapter helper
  -> generated _BenchmarkDiscovery / explicit suites
  -> adapter/helper enters BenchmarkRunner.Plan / BenchmarkRunner
  -> ReportDocument
  -> Issue.record / Attachment.record on adapter output
```

Swift Testing provides the declaration and trait mental model, but Swift
Testing's native runner is not the Benchmark runner. Package workflow bridges
supported Testing declarations into Benchmark discovery records and then enters
the local Benchmark runner to preserve warmup, repeated measured iterations,
samples, Dimension expansion, Report comparison, and diagnostics evidence.

Native Benchmark execution path:

```text
@BenchmarkSuite / @Benchmark
  -> _BenchmarkDiscovery
  -> BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> ReportDocument
```

```swift
@Suite(.benchmark(.iterations(100)))
struct ParserPerformanceTests {
  @Test(.benchmark(.time(max: .milliseconds(30))))
  func parseSmallDocument() throws {
    try parser.parse(input)
  }
}
```

Adapter rules:

- Swift Testing depends on Benchmark core; Benchmark core does not depend on
  Swift Testing.
- `@Suite(.benchmark...)` can provide suite-level benchmark traits inherited by
  contained tests.
- `@Test(.benchmark...)` can provide case-level benchmark traits that override,
  refine, or add to suite-level traits.
- `@Suite`/`@Test(.benchmark...)` should wrap benchmark execution, budgets, and
  issue reporting around generated `BenchmarkCase`, `BenchmarkSuite`, and
  `BenchmarkRunner`.
- Traits may expose Testing-native ergonomics such as `.benchmark(...)`,
  performance budgets, grouping, and failure reporting.
- Testing traits must not replace the core runner, sample model,
  `Benchmark.Measurement`, or structured result model.
- `swift package benchmark` remains the primary production benchmark command;
  Swift Testing/XCTest adapters are ecosystem integration paths over
  `ReportDocument`.
- Architecture keeps the adapter boundary visible; adapters remain consumers of
  Benchmark/Report.

## Target Architecture Scope

Benchmark absorbs official Apple/Swift alignment and approved local
reconstruction decisions into a coherent product layer. Durable architecture
facts record local concepts only. The core product layer includes:

- elegant declaration model,
- Swift-Testing-aligned discovery and plan model,
- benchmark suite / benchmark case model,
- runner,
- warmup,
- measured iteration policy,
- wall-clock measurement,
- monotonic clock abstraction,
- samples,
- `Benchmark.Measurement` rows,
- `Benchmark.Dimension` single input-size model,
- structured result model,
- `blackHole`.

The following concerns are Benchmark-adjacent product/adaptor boundaries:

- baseline file format and regression policy,
- CI regression gates,
- SwiftPM command plugin,
- Report structured output and stable JSON export,
- Swift Testing adapter,
- XCTest adapter,
- Report Dimension curves,
- Memory/allocation metrics,
- Instruments timeline aggregation.

Completion is measured by tests and workflow evidence, not by the existence of
type names alone.

## Report And Baseline Boundary

Benchmark produces structured results.

Report structures, compares, attributes, renders summaries, and exports
structured results.
Baseline/regression compares current results to saved historical results.
Single-run budgets compare current Report metrics to explicit thresholds without a
saved baseline. These are important product directions, but they are separate
from the core runner semantics.

Do not collapse Report rendering, baseline storage, or CI regression gates into
the core Benchmark runner. They belong to Report, CLI/plugin, and adapter
layers.

Report output should include:

- `BenchmarkResult` facts: suite, case, configuration, raw samples,
  measurement rows, duration units, and execution status,
- run metadata: Swift version, package/git identity, platform, architecture, OS,
  date/time, build configuration, and optional device metadata,
- baseline/regression data: baseline value, absolute delta, percentage delta,
  threshold policy, pass/fail verdict, and context,
- budget data: metric selector, actual value, limit, delta, and verdict,
- source locations for benchmark declarations where available,
- timeline attribution when available,
- diagnostics metrics and attachments when available,
- structured states for measured, not configured, unavailable, and failed
  diagnostics.

Output consumers must consume the same typed Report model:

- console summary for local use,
- JSON for machines and CI,
- profiler/exporter-compatible outputs such as speedscope/flamegraph records.

Markdown, HTML, CSV, JMH, Influx, HDR, or other non-core exporter breadth is not
Benchmark core and is not the primary Report contract. Those outputs can be
generated by optional templates, tools, MCPs, or agents over stable JSON.

The CLI or SwiftPM plugin should call Report output contracts. It should not
invent a separate result model.

## Optional Relationship With Instruments

Expected optional flow:

```text
Benchmark runner
  -> configure InMemoryRecorder
  -> run workload
  -> snapshot Timeline
  -> associate snapshot data with iteration/sample scope
  -> Report aggregates per-span metrics
```

This integration path is optional and does not make Benchmark an
instrumentation, tracing, Signpost, or span system.

Timeline correlation should bind each measured sample to the spans/events that
occurred during the same benchmark iteration. This allows reports to attribute a
slow sample to user-visible phases such as `Tokenize`, `ParseAST`, or
`WriteCache` instead of only showing that a case became slower.

## Diagnostics Adapter Boundary

Diagnostics adapters enrich Report. They do not replace Benchmark core and do
not become Instruments public APIs.

Potential adapter responsibilities:

- `BenchmarkObserver`: observes suite/case/iteration lifecycle events for
  optional integrations.
- `TimelineCorrelator`: maps Benchmark samples to Instruments timelines through
  public snapshots and correlation IDs.
- `MetricProvider`: gathers optional metrics such as CPU, memory, allocation,
  I/O, or future platform metrics.
- `TraceExporter`: records or links diagnostic artifacts such as Instruments
  traces.
- `ReportAttributor`: derives report-ready attribution from samples, spans,
  metrics, and attachments.

Platform policy:

- Benchmark, measurement rows, result schema, baseline diff, Report schema,
  JSON, and summary rendering should remain portable.
- Apple platform diagnostics may use Signpost timelines and Instruments trace
  artifacts behind platform-checked adapter/backend files. Future production
  diagnostics may add MetricKit payload evidence.
- Unsupported optional diagnostics report structured unavailable states.
- Unsupported required diagnostics fail configuration explicitly.
- Never report unsupported metrics as zero.

`SignpostRecorder` and `os_signpost` remain Apple backend plumbing. Timeline
correlation may observe benchmark iterations through public hooks, but Signpost
must not become a product domain or leak into Benchmark core.

## Risks / Ongoing Extension Points

- Optional platform providers and presentation templates may grow, but they
  should remain Report/adapters over the structured evidence model.
- Durable official-source alignment belongs in architecture documents.

## Related Documents

- `ProductDomains.md`
- `Instruments.md`
