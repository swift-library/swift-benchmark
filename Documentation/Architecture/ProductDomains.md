# Product Domains

## Scope / Purpose

This document is the current product-domain map for `swift-benchmark`.

The repository is a Swift performance toolkit. Product-domain truth lives here
first; layer-specific architecture documents describe their own boundaries
without redefining the full map.

## Context / Boundaries

`swift-benchmark` has these product domains:

- `Instruments`
- `InstrumentsMacros`
- `Benchmark`
- `Report`
- `BenchmarkTesting`
- `BenchmarkXCTest`
- CLI / SwiftPM plugin
- Apple diagnostics

These boundaries hold Instruments-first runtime and macro alignment, Benchmark
measurement with built-in and custom metrics, the package workflow with
declaration macros, runner plans, event streams and per-step host processes,
Report comparisons with warnings, Testing/XCTest adapters, Dimension, and
xctrace trace attachments.

Further work should evolve these product boundaries rather than creating new
top-level domains for unrelated implementation topology.

## Completed Foundation And Current Scope

Completed foundation:

1. Instruments-first runtime and macro alignment.
2. Benchmark runner and structured result model.
3. First-pass Report, CLI/plugin, adapter, Dimension/input-size analysis,
   and implementation planning.

Implemented scope:

1. Real declaration-driven `swift package benchmark` workflow.
2. Apple/Swift-Testing-aligned declaration, discovery, plan, and runner
   skeleton: `@BenchmarkSuite` / `@Benchmark` -> `_BenchmarkDiscovery` ->
   `BenchmarkDiscovery` -> `BenchmarkRunner.Plan` -> `BenchmarkRunner`.
3. Swift Testing and XCTest native adapter UX over Benchmark/Report.
4. Apple-aligned Dimension workflow and Report-backed curve/comparison model.
5. Report-owned baseline, budget, diff, check, and stable JSON reports.
6. Credible measurement: wall-clock and CPU time, Swift allocation and
   reference counting, peak memory and custom metrics; automatic batching;
   per-step host processes; per-row, per-metric comparisons; and warnings for
   unreliable comparisons.
7. xctrace recording and trace attachments as Report data.

The implemented scope is complete within the accepted boundaries. It
does not copy unrelated package structure, result formats, or private platform
hooks.

## Current Structure

Current package facts:

- Package name: `swift-benchmark`.
- Public products today: `Instruments`, `Benchmark`, `Report`,
  `BenchmarkTesting`, and `BenchmarkXCTest`.
- Package traits today: `Macros`, enabled by default, declares the Instruments
  macros; without it Instruments builds without swift-syntax.
- Executable/plugin products today: `swift-benchmark-cli`,
  `BenchmarkCLI`, and `BenchmarkPlugin`.
- Package workflow implementation tools today: `BenchmarkDiscoveryTool` and
  `_BenchmarkDiscoveryCore`. They are not public product domains.
- Runtime/API target today: `Sources/Instruments`.
- Macro implementation target today: `Sources/InstrumentsMacro`.
- Benchmark target today: `Sources/Benchmark`.
- Report and adapter targets today: `Sources/Report`,
  `Sources/BenchmarkTesting`, `Sources/BenchmarkXCTest`,
  `Sources/BenchmarkCLI`, `Sources/BenchmarkDiscoveryTool`,
  `Sources/_BenchmarkDiscoveryCore`, and `Plugins/BenchmarkPlugin`.
- Tests today: `Tests/InstrumentsTests`, `Tests/BenchmarkTests`,
  `Tests/ReportTests`, `Tests/AdapterTests`, `Tests/BenchmarkDiscoveryCoreTests`,
  and `Tests/WorkflowTests`.

The current source code is Instruments-first. Signpost is an Apple backend
inside Instruments rather than a product domain.

## Domain Boundaries

### Benchmark

Benchmark is repeatable workload measurement for test, benchmark, and CI
workflows.

It owns:

- `@BenchmarkSuite` and `@Benchmark` primary user-facing declarations,
- `BenchmarkSuite` and `BenchmarkCase` internal/SPI or advanced lowering
  targets,
- `_BenchmarkDiscovery` as an internal/SPI discovery substrate for generated
  benchmark records,
- `BenchmarkDiscovery` as the materialized discovery result for tooling and
  package workflows,
- `BenchmarkRunner.Plan`, `BenchmarkRunner.Plan.Step`, and
  `BenchmarkRunner.Plan.Action`,
- declaration metadata needed for discovery and planning,
- runner policies,
- warmup,
- batching,
- measured iterations,
- samples,
- built-in metrics (wall-clock and CPU time, Swift allocation and reference
  counting, peak memory) and custom metrics recorded by workloads,
- `Benchmark.Measurement` rows and samples,
- `Benchmark.Dimension` single input-size metadata,
- structured results,
- execution hooks for optional observers.

Benchmark may expose public hooks that Report can observe, but it must not own
baseline storage, renderer policy, platform diagnostics, or Instruments runtime
behavior.

Benchmark is not normal production app flow and is not the runtime
instrumentation layer. It exposes execution hooks that Report can combine with
optional Instruments timelines, but its runner lives in the Benchmark layer
rather than the Instruments runtime.

### Instruments

Instruments is runtime-safe instrumentation for production and test code.

It owns:

- spans,
- events,
- recorders,
- timeline,
- attributes/context,
- platform backends.

Signpost is not a top-level product domain. Signpost is the Apple backend
inside Instruments.

Instruments macros are observability APIs. They do not declare benchmarks and
must not automatically become benchmark discovery metadata.

### InstrumentsMacros

InstrumentsMacros is macro ergonomics for Instruments.

It owns:

- `#span`,
- `#event`,
- `@Instrumented`,
- `@InstrumentedMembers`,
- `@Span`.

Macros should emit Instruments semantics. They should not emit Signpost
semantics directly. The package's `Macros` trait declares them; the runtime
API they expand to works without them, so production code can depend on
Instruments without building swift-syntax.

`@Span` is the function/initializer-level body macro. Function/initializer-level
`@Instrumented` is ergonomic syntax over the same span semantics with a default
stable name.
Type/extension bulk instrumentation is exposed as `@InstrumentedMembers`, which
applies `@Span("Type.member")` to eligible methods and initializers in the
annotated declaration body. The current Swift macro system rejects one public
`@Instrumented` macro name that is both a function `body` macro and a type
`memberAttribute` macro;
`Documentation/Architecture/Instruments.md` records the compiler evidence behind the
split.

### Benchmark Declaration Macros

Benchmark declaration macros are the Benchmark-facing ergonomics layer, not
Instruments macros and not Swift Testing runtime APIs. Current source lowers
trait arguments, tags, parameter-aware Dimension methods, generated discovery
sidecars, and source-location metadata into Benchmark discovery records.

They are the primary user-facing Benchmark authoring UX. The programmatic
`BenchmarkSuite` / `BenchmarkCase` model remains the underlying model for tools,
adapters, generated metadata, fixtures, and advanced APIs, but it should not be
the ordinary user's first mental model and does not need to be stabilized as a
public-first authoring contract.

They should own:

- `@BenchmarkSuite`,
- `@Benchmark`,
- suite-level `BenchmarkSuiteTrait` input,
- case-level `BenchmarkCaseTrait` input,
- compile-time metadata that lowers to `BenchmarkSuite` and
  `BenchmarkCase` / `Benchmark`,
- discoverable records for `_BenchmarkDiscovery`,
- source-location capture at the user declaration.

They must not:

- depend on Swift Testing runtime,
- use global mutable registration as architecture truth,
- auto-insert `#span` or `@Instrumented`,
- introduce `BenchmarkTask` as the local core model,
- expose a global `benchmark("Name") { ... }` function as the product entry
  point,
- expose `Provider` / `Probe` as the user-facing package workflow model.

### Report

Report provides structured report data, comparison, attribution, trace
attachments, and export. It owns the report graph that explains regressions and feeds
agent/tool/UI/profiler-compatible outputs.

It owns:

- typed report documents,
- stable JSON schema,
- Swift-Testing-style event collection consumers over `Benchmark.Event`, such
  as `ReportRecorder` and `ReportBuilder`,
- run/environment metadata,
- raw result projection,
- timeline aggregation,
- per-row, per-metric baseline comparisons,
- single-run budget verdicts,
- regression verdicts,
- warnings about unreliable comparisons,
- CI verdict data,
- trace attachments,
- structured outputs and exporter-compatible records.

Swift code should not treat hardcoded HTML/Markdown presentation as the core
value. HTML or Markdown can be optional template or agent-driven artifacts over
the structured report model. The public Swift contract is the data shape and
export contract, not presentation authoring.

Report consumes data produced by Benchmark and Instruments, and trace
artifacts. It does not own the runtime recording model and does not replace the
Benchmark runner.

Report naming should follow Swift Testing's event/recorder style when concepts
match, but should not nest just for aesthetics. `Benchmark.Event`,
`Benchmark.Event.Kind`, `Benchmark.Event.Context`, and
`Benchmark.Event.Stream` belong to the benchmark lifecycle. `ReportRecorder`
consumes those events and constructs or enriches `ReportDocument`. Console
recorders are human output; stable machine truth remains `ReportDocument` JSON.

Report data should be correlated by stable scopes:

```text
Run -> Suite -> Case -> Row -> Sample -> Span/Event
                     -> Attachment
```

This lets users drill from a regression summary to the row, sample, metric,
internal phase, and trace that explain the result.

### Benchmark Dimension

Dimension is Benchmark's first-class input-size measurement model.

The user-facing Dimension model is trait-driven parameterization over
Benchmark declarations. Users write `.dimension(sizes: [10, 100])` on a
`@Benchmark` method that takes a `Benchmark.Scale`; discovery preserves
`Benchmark.Dimension` metadata; `BenchmarkRunner.Plan` expands each
`Benchmark.Scale` into executable steps; `Benchmark.Event.Context`
carries Dimension context; and `Benchmark.Measurement` stores rows and samples.

It owns:

- `.dimension(sizes:)` / `Benchmark.Dimension.Trait` case-trait semantics,
- `Benchmark.Scale` as an Apple-aligned `Int` wrapper,
- one generator per size, run outside measured iterations,
- single-Dimension plan expansion,
- `Benchmark.Measurement.Row(size:samples:)`,
- ordinary benchmark rows with `size == nil`,
- Dimension benchmark rows with one row per size,
- `Benchmark.Dimension.amortized(...)` semantics.

Report owns the derived projection: `Report.Measurement`,
`Report.Measurement.Row` statistics, `Report.Statistic`, and
`Report.DimensionCurve`. A Dimension curve is a structured record of one
statistic of one metric over measurement rows; it is not a Swift-owned
presentation renderer.

Input-size curve behavior is implemented through Benchmark Dimension and
Report DimensionCurve. There is no separate input-size product domain or
compatibility shim.

Lower-level input-size and amortized semantics follow Apple
`swift-collections-benchmark`. The declaration, trait, and plan experience
follows Swift Testing.

### Testing And XCTest

`BenchmarkTesting` and `BenchmarkXCTest` are adapters over Benchmark/Report.

They own:

- Swift Testing trait-level UX where the public Testing surface allows it,
- Swift Testing `@Suite(.benchmark...)` suite-level traits where supported,
- Swift Testing `@Test(.benchmark...)` case-level traits where supported,
- inheritance and merge behavior from suite-level benchmark traits into
  contained Testing tests,
- in-process measurement that reports through the same `ReportDocument`,
- XCTest issue/failure/attachment integration,
- source-location-aware failures,
- budget/baseline/allocation verdict presentation,
- structured report artifacts.

They remain consumers of Benchmark/Report and do not replace the Benchmark
runner.

### CLI / SwiftPM Plugin

The CLI and SwiftPM plugin are workflow entry points over Benchmark and Report.

They own:

- declaration discovery through `_BenchmarkDiscovery` / `BenchmarkDiscovery`
  in a runnable host,
- `BenchmarkRunner.Plan` construction from filters, traits, configuration, and
  selected benchmark cases,
- `list`,
- `run`,
- `check`,
- `baseline write/update`,
- `diff`,
- `trace`,
- filters and execution overrides,
- one host process per measured step, and one traced process for xctrace,
- comparison, budgets, the debug-build gate and rendering,
- output paths,
- trace flags,
- quiet/progress separation,
- documented exit codes.

The package command should enter user code through declaration metadata exposed
by a generated Benchmark host. Library target `@BenchmarkSuite` declarations
lower to `_BenchmarkDiscovery`; supported test-target `@Suite(.benchmark...)` /
`@Test(.benchmark...)` declarations are bridged into generated
`_BenchmarkDiscovery` records. Code declarations remain the source of truth;
users should not maintain separate manifest/config files, target naming
conventions, or public provider boilerplate just to make benchmarks
discoverable.

Package workflow vocabulary should match Swift Testing's architecture shape:

```text
declaration -> discovery -> runner plan -> runner -> report
```

`Provider` and `Probe` are not package workflow concepts. If probe-style
terminology is used, it belongs to diagnostics collection, not benchmark
discovery.

### Apple Diagnostics

Apple diagnostics enrich Report and remain optional. They own `xcrun xctrace
record` orchestration and Instruments trace attachments; Report owns the
Benchmark/Instruments timeline correlation they sit beside. The `.trace`
package is an attachment with provenance, not a data model to parse.

Apple diagnostics do not belong in Benchmark core or Instruments runtime.

## Key Principles

- Keep Benchmark and Instruments separate: repeatable measurement is not the
  same as runtime instrumentation.
- Keep Instruments and Report separate: runtime recording is not rendering or
  aggregation.
- Keep Signpost inside Instruments as a backend, not a product domain.
- Keep macro APIs named for their semantic layer: Instruments macros instrument;
  Benchmark macros declare benchmarks.
- Keep adapter and diagnostics domains out of Instruments runtime.
- Keep Benchmark as its own layer, not as Instruments runtime behavior.
- Treat Benchmark as a Swift-Testing-style performance specialization: Swift
  Testing provides the primary declaration/discovery/plan/runner architecture,
  and benchmark-specific measurement, metric, Dimension, and report
  capabilities extend that skeleton.
- Keep Benchmark discovery/plan/runner aligned with Swift Testing naming and
  architecture while preserving benchmark-specific execution semantics.
- Keep Apple diagnostics Report-facing; they explain benchmark results but do
  not define Benchmark core.
- Keep `ReportDocument` JSON as the stable exchange contract.
- Keep architecture alignment references limited to Apple/Swift official
  sources.

## Risks / Extension Points

- Same-name type-level `@Instrumented` is blocked by current macro
  attachment-role constraints; `@InstrumentedMembers` is the accepted
  implemented spelling for Instruments bulk instrumentation.
- Package-level `swift package benchmark` discovery is implemented through an
  internal generated host bridge for library targets and through the
  BenchmarkTesting bridge for supported test-target `@Suite(.benchmark...)` /
  `@Test(.benchmark...)` declarations. Executable-only declarations still need
  the advanced `--host` override or should be moved into a discoverable library
  target.
- Testing/XCTest adapter depth depends on public Testing/XCTest surfaces and
  must stay behind compile/availability gates.
- Swift counting metrics depend on the Swift runtime's instrumentation hooks
  on Apple platforms and on the interposer library in a counting process on
  Linux, and heap metrics need the interposer on both; peak memory is
  attributable to a step only in a process that measures nothing else.
- `xctrace` behavior is Apple-tooling-dependent and must remain optional Report
  diagnostics.
- Future presentation templates may grow, but they should remain artifacts over
  the structured report model rather than new product semantics.

## Related Documents

- `Benchmark.md`
- `Instruments.md`
- `Report.md`
- `../Migrations/SignpostToInstruments.md`
