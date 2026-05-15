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
- `Memory`
- `BenchmarkTesting`
- `BenchmarkXCTest`
- CLI / SwiftPM plugin
- platform diagnostics adapters

The completed foundation delivered Instruments-first runtime/macro alignment
and Benchmark core measurement. The Benchmark pass has now
extended the same boundaries with package workflow, declaration macros, runner
plans, event streams, baseline/regression, Testing/XCTest adapters, Dimension,
Memory/allocation, and diagnostics adapters.

Further work should evolve these product boundaries rather than creating new
top-level domains for unrelated implementation topology.

## Completed Foundation And Current Scope

Completed foundation:

1. Instruments-first runtime and macro alignment.
2. Benchmark runner and structured result model.
3. First-pass Report, CLI/plugin, adapter, Dimension/input-size analysis,
   Memory, diagnostics, and implementation planning.

Implemented scope:

1. Real declaration-driven `swift package benchmark` workflow.
2. Apple/Swift-Testing-aligned declaration, discovery, plan, and runner
   skeleton: `@BenchmarkSuite` / `@Benchmark` -> `_BenchmarkDiscovery` ->
   `BenchmarkDiscovery` -> `BenchmarkRunner.Plan` -> `BenchmarkRunner`.
3. Swift Testing and XCTest native adapter UX over Benchmark/Report.
4. Apple-aligned Dimension workflow and Report-backed curve/comparison model.
5. Report-owned baseline, budget, diff, check, and stable JSON evidence.
6. Memory/allocation provider depth and resource-regression discipline.
7. Optional Apple diagnostics as Report evidence and trace artifacts.

The implemented scope is complete within the accepted boundaries. It
does not copy unrelated package structure, result formats, or private platform
hooks.

## Current Structure

Current package facts:

- Package name: `swift-benchmark`.
- Public products today: `Instruments`, `Benchmark`, `Report`, `Memory`,
  `BenchmarkTesting`, and `BenchmarkXCTest`.
- Executable/plugin products today: `swift-benchmark-cli`,
  `BenchmarkCLI`, and `BenchmarkPlugin`.
- Package workflow implementation tools today: `BenchmarkDiscoveryTool` and
  `_BenchmarkDiscoveryCore`. They are not public product domains.
- Runtime/API target today: `Sources/Instruments`.
- Macro implementation target today: `Sources/InstrumentsMacro`.
- Benchmark target today: `Sources/Benchmark`.
- Report and adapter targets today: `Sources/Report`, `Sources/Memory`,
  `Sources/BenchmarkTesting`, `Sources/BenchmarkXCTest`,
  `Sources/BenchmarkCLI`, `Sources/BenchmarkDiscoveryTool`,
  `Sources/_BenchmarkDiscoveryCore`, and `Plugins/BenchmarkPlugin`.
- Tests today: `Tests/InstrumentsTests`, `Tests/BenchmarkTests`,
  `Tests/ReportTests`, `Tests/MemoryTests`, `Tests/AdapterTests`, and
  `Tests/WorkflowTests`.

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
- measured iterations,
- samples,
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
semantics directly.

`@Span` is the function-level body macro. Function-level `@Instrumented` is
ergonomic syntax over the same span semantics with a default stable name.
Type/extension bulk instrumentation is exposed as `@InstrumentedMembers`, which
applies `@Span("Type.method")` to eligible methods in the annotated declaration
body. The current Swift macro system rejects one public `@Instrumented` macro
name that is both a function `body` macro and a type `memberAttribute` macro;
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

Report is structured evidence, comparison, attribution, diagnostics, and
export. It owns the evidence graph that explains regressions and feeds
agent/tool/UI/profiler-compatible outputs.

It owns:

- typed report documents,
- stable JSON schema,
- Swift-Testing-style event collection consumers over `Benchmark.Event`, such
  as `ReportRecorder`, `ReportBuilder`, and `ReportDocumentEncoder`,
- run/environment metadata,
- raw result projection,
- timeline aggregation,
- baseline diffs,
- single-run budget verdicts,
- regression verdicts,
- CI verdict data,
- diagnostics metrics and attachments,
- structured outputs and exporter-compatible records.

Swift code should not treat hardcoded HTML/Markdown presentation as the core
value. HTML or Markdown can be optional template or agent-driven artifacts over
the structured report model. The public Swift contract is the data shape and
export contract, not presentation authoring.

Report consumes data produced by Benchmark, Instruments, and optional
diagnostics adapters. It does not own the runtime recording model and does not
replace the Benchmark runner.

Report naming should follow Swift Testing's event/recorder style when concepts
match, but should not nest just for aesthetics. `Benchmark.Event`,
`Benchmark.Event.Kind`, `Benchmark.Event.Context`, and
`Benchmark.Event.Stream` belong to the benchmark lifecycle. `ReportRecorder`
consumes those events and constructs or enriches `ReportDocument`. Console
recorders are human output; stable machine truth remains `ReportDocument` JSON.

Report data should be correlated by stable scopes:

```text
Run -> Suite -> Case -> Iteration/Sample -> Span/Event -> Metric/Attachment
```

This lets users drill from a regression summary to the sample, internal phase,
metric, and diagnostic artifact that explain the result.

### Benchmark Dimension

Dimension is Benchmark's first-class input-size measurement model.

The user-facing Dimension model is trait-driven parameterization over
Benchmark declarations. Users write `.dimension(sizes: [10, 100]) { size in
makeInput(size) }` on `@Benchmark`; discovery preserves
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
`Report.Measurement.Row.metrics`, `Report.Measurement.Metric`, and
`Report.DimensionCurve`. A Dimension curve is a structured record over
measurement rows and a selected metric; it is not a Swift-owned presentation
renderer.

Input-size curve behavior is implemented through Benchmark Dimension and
Report DimensionCurve. There is no separate input-size product domain or
compatibility shim.

Apple `swift-collections-benchmark` remains the trusted source for lower-level
input-size and amortized semantics. Swift Testing remains the trusted source
for the declaration/trait/plan user experience.

### Memory

Memory owns memory and allocation providers over Benchmark/Report.

It owns:

- resident memory metrics such as RSS/physical memory,
- allocator metrics such as allocated bytes, deallocation counts, net
  allocations, peak allocated bytes, and leak/tolerance data,
- provider unavailable/notConfigured/failed/measured states,
- resource-regression discipline suitable for Testing/XCTest and CLI verdicts.

Resident memory and allocator metrics are separate dimensions. Unsupported data
must not be reported as zero.

### Testing And XCTest

`BenchmarkTesting` and `BenchmarkXCTest` are adapters over Benchmark/Report.

They own:

- Swift Testing trait-level UX where the public Testing surface allows it,
- Swift Testing `@Suite(.benchmark...)` suite-level traits where supported,
- Swift Testing `@Test(.benchmark...)` case-level traits where supported,
- inheritance and merge behavior from suite-level benchmark traits into
  contained Testing tests,
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
- output paths,
- diagnostics flags,
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

### Platform Diagnostics Adapters

Diagnostics adapters enrich Report and remain optional.

They may own:

- Benchmark lifecycle observation,
- Benchmark/Instruments timeline correlation,
- future MetricKit collection where available,
- memory/allocation metric collection,
- Instruments trace artifact orchestration,
- future platform metric providers.

Diagnostics adapters do not belong in Benchmark core or Instruments runtime.
Unsupported optional diagnostics should produce structured unavailable states,
not fake zero values. Unsupported required diagnostics should fail
configuration explicitly.

MetricKit is future Apple-only optional Report evidence. It is run/app-session
scoped, must not be promised as deterministic per-iteration benchmark data, and
is not current Benchmark closure acceptance.

`xcrun xctrace record` orchestration is an optional diagnostics workflow. The
`.trace` package and exported public metadata are attachments/provenance, not a
stable private data model to parse.

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
  and benchmark-specific measurement, Dimension, report, memory, and diagnostics
  capabilities extend that skeleton.
- Keep Benchmark discovery/plan/runner aligned with Swift Testing naming and
  architecture while preserving benchmark-specific execution semantics.
- Keep diagnostics adapters Report-facing; they explain benchmark results but
  do not define Benchmark core.
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
- Memory/allocation provider behavior varies by platform and toolchain.
- `xctrace` behavior is Apple-tooling-dependent and must remain optional Report
  evidence. MetricKit remains future optional production diagnostics evidence.
- Future presentation templates may grow, but they should remain artifacts over
  the structured evidence model rather than new product semantics.

## Related Documents

- `Benchmark.md`
- `Instruments.md`
- `Report.md`
- `../Migrations/SignpostToInstruments.md`
