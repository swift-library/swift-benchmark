# swift-benchmark

`swift-benchmark` is a Swift performance toolkit. Its accepted architecture
separates runtime instrumentation from repeatable measurement:

- `Instruments`: runtime-safe instrumentation for production and test code.
- Instruments macro ergonomics provided through the `Instruments` product.
- `Benchmark`: repeatable workload measurement for test, bench, and CI.
- `Report`: structured performance evidence, baseline comparison, attribution,
  diagnostics, and rendering.
- `Memory`, `BenchmarkTesting`, and `BenchmarkXCTest`: adapter layers over
  Benchmark and Report.

The implemented current scope includes:

1. Instruments-first runtime and macro alignment.
2. Swift-Testing-shaped Benchmark declarations, traits/tags, discovery, runner
   plans, event streams, fixed/adaptive measurement, and structured Dimension
   measurement.
3. Report JSON, baseline/budget checks, Dimension curves, adapter helpers,
   Memory/allocation evidence, xctrace/Instruments trace evidence, and
   host-backed plus no-host SwiftPM package workflows.

The accepted active architecture is Dimension-first: `Benchmark.Dimension`
describes one input-size measurement dimension, `Benchmark.Measurement`
preserves the measured rows and samples, and `Report.Measurement` projects that
truth into derived metrics, baselines, budgets, and `Report.DimensionCurve`
records.

Signpost is not a product domain; it is the Apple backend that should live
behind the Instruments recorder model. Benchmark remains a separate product
domain and should not be folded into the Instruments runtime layer.

## Install

```swift
// Package.swift
.dependencies: [
  .package(url: "https://github.com/swift-library/swift-benchmark.git", from: "0.1.0"),
],
.targets: [
  .target(
    name: "YourTarget",
    dependencies: [
      .product(name: "Instruments", package: "swift-benchmark"),
      .product(name: "Benchmark", package: "swift-benchmark"),
      .product(name: "Report", package: "swift-benchmark"),
    ]
  )
]
```

## Current Status

This repository has completed the Instruments-first foundation and the
Benchmark/Report/package workflow target for the current
scope. Within that scope, source authority is tiered: Apple/Swift official
APIs, tools, and open-source packages may be durable architecture alignment
references. README and architecture truth record the local model.

Current package facts:

- The public `Instruments` product exists.
- The public `Benchmark` product exists.
- The public `Report`, `Memory`, `BenchmarkTesting`, and `BenchmarkXCTest`
  products exist.
- The executable products `swift-benchmark-cli` and `BenchmarkCLI` exist;
  `BenchmarkCLI` is also used by the SwiftPM command plugin.
- The `BenchmarkPlugin` command plugin exists.
- `SignpostMacros` and public Signpost-named macro APIs have been removed.
- `#span`, `#event`, `@Span`, function-level `@Instrumented`,
  type/extension-level `@InstrumentedMembers`, `Recorder`, `SpanToken`,
  `SpanAttributes`, `Timeline`, `InMemoryRecorder`, `EmptyRecorder`, and
  `SignpostRecorder` are implemented.
- `@BenchmarkSuite`, `@Benchmark`, `_BenchmarkDiscovery`,
  `BenchmarkDiscovery`, `BenchmarkSuite`, `BenchmarkCase`, `BenchmarkRunner`,
  `BenchmarkRunner.Plan`, `BenchmarkConfiguration`, `WarmupPolicy`,
  `IterationPolicy`, `BenchmarkClock`, `Sample`, `Benchmark.Measurement`,
  `BenchmarkResult`, `Benchmark.Dimension`, `Benchmark.Event.Stream`,
  trait/tag/scoping support, and `blackHole` are implemented.
  Macro trait lowering covers source locations, tags, parameterized Dimension
  methods, and generated discovery sidecars. Runner plans support measure,
  skip, planning-failure actions, tag filters, and adaptive/min/max-duration
  policies.
- `ReportDocument`, run metadata, sample/metrics projection, schema fixtures,
  baseline comparison, single-run budgets, structured verdict causes, source
  locations, timeline attribution, diagnostic states, diagnostic attachments,
  JSON/Markdown/console/speedscope consumers, `Report.Measurement`,
  `Report.DimensionCurve`, `ReportRecorder`, `ReportBuilder`, and
  `BenchmarkCommand` are implemented.
- CLI/plugin workflows cover host-backed and no-`--host` package
  list/run/check/trace, file-based render/compare/diff/baseline
  write/update/check, tag filters, warmup/iteration/adaptive overrides,
  diagnostics flags, trace artifacts, output paths, quiet output, and stable CI
  exit codes.
- Input-size parameterization, metric selectors, Dimension curves, resident and
  allocation diagnostic providers, resource/FD leak checks, `xctrace record`
  orchestration, trace attachment provenance, Swift Testing trait/adapter
  helpers, and XCTest adapter helpers are implemented over Benchmark/Report.
- MetricKit remains future optional production diagnostics evidence, not current
  Benchmark closure acceptance.
- Type/extension bulk instrumentation is exposed as `@InstrumentedMembers`
  because Swift currently rejects one public `@Instrumented` macro name spanning
  both function `body` and type `memberAttribute` roles. See
  `Docs/Architecture/Instruments.md` for the recorded compiler evidence.

Important boundaries:

- `Benchmark` measures and stays portable.
- `Report` compares, attributes, diagnoses, and exports structured evidence.
- Apple diagnostics enter as optional Report diagnostics/attachments.
- Swift-owned hardcoded HTML is not the core deliverable; structured JSON and
  exporter-compatible records are the stable contract.
- See `Docs/Architecture/ImplementationScope.md` for the implemented
  capability matrix and remaining future boundaries.

## Instruments Model

The public API is Instruments-first:

```swift
import Instruments

#span("BuildIndex") {
  buildIndex()
}

#event("CacheMiss")

@Instrumented
func openProject() async throws -> Project {
  ...
}

@Span("BuildIndex")
func buildIndex() throws -> Index {
  ...
}

@InstrumentedMembers
struct Store {
  func load() throws -> Item {
    ...
  }
}
```

Semantics:

- `#span` records a duration-bearing operation.
- `#event` records a point-in-time marker.
- Function-level `@Instrumented` and `@Span` are real attached function-body
  macros.
- Function-level `@Instrumented` is ergonomic syntax over `@Span` with a default
  stable name.
- `@InstrumentedMembers` bulk-applies `@Span("Type.method")` to eligible methods
  declared directly in the annotated type or extension.
- Macros should expand to Instruments runtime APIs, not directly to
  `OSSignposter` or `os_signpost`.
- Span and event names should be stable `StaticString` operation names.
  Dynamic context belongs in attributes.
- Spans should end exactly once across success, thrown error, and cancellation
  paths where `defer` runs.

## Runtime Model

The Instruments runtime owns spans, events, recorders, timelines, attributes,
context, disabled/fallback behavior, and platform backends.

The runtime implementation includes:

- a sync-friendly `Recorder` abstraction,
- backend state represented by `SpanToken`,
- small dynamic metadata through `SpanAttributes`,
- a cheap disabled/fallback `EmptyRecorder`,
- supported Apple platform recording through `SignpostRecorder`,
- `Timeline` and `InMemoryRecorder` inside Instruments for later Benchmark
  and Report integration,
- nested-span and parent/child context direction without building a
  full distributed tracing system.

Benchmark runner behavior is not part of the Instruments alignment pass. It is
the second implementation target and belongs in the Benchmark product boundary.

## Benchmark Model

The `Benchmark` product is repeatable workload measurement informed by the
official Apple/Swift alignment recorded in `Docs/Architecture/`.
The target user-facing authoring model is Swift-Testing-style macro declaration:

```swift
import Benchmark

@BenchmarkSuite("Parser")
struct ParserBenchmarks {
  @Benchmark("Parse document")
  func parseDocument() throws {
    try parser.parse(input)
  }

  @Benchmark
  func tokenize() {
    tokenizer.tokenize(input)
  }
}
```

Benchmark core supports suite/case declarations, warmup, measured iterations,
wall-clock samples, measurements, structured results, and `blackHole` for
non-`Void` workload returns.

Dimension-first measurement is the accepted target:

```swift
Benchmark(
  "Parse document",
  dimension: Benchmark.Dimension(sizes: [10, 100]),
  input: { size in makeInput(size) }
) { input in
  try parser.parse(input)
}
```

`Benchmark.Dimension.Size` is an Apple-aligned `Int` wrapper. The generator is
run once per size to produce input and is not counted as a measured iteration.
`Benchmark.Measurement` is the measurement truth: ordinary benchmarks produce
one row with `size == nil`; dimension benchmarks produce one row per size with
the measured samples for that size.

The Benchmark layer owns its runner and measurement model. Report consumes
Benchmark results, Benchmark execution hooks, and optional Instruments timelines
for attribution; Benchmark itself does not depend on Instruments internals or
become runtime instrumentation.

Swift Testing and XCTest adapter helpers are implemented over Benchmark core,
not as the core runner model. `BenchmarkSuite` and `BenchmarkCase` are the
underlying advanced/programmatic model and macro lowering target, not the
ordinary user's first authoring surface.

## Report Model

`Report` turns benchmark results into a correlated performance evidence model:

```text
@BenchmarkSuite / @Benchmark
  -> BenchmarkRunner.Plan
  -> Benchmark.Event.Stream
  -> ReportDocument
  -> CLI / plugin / Testing / XCTest / agent outputs
```

`Benchmark.Event.Stream` is the live execution stream. `ReportRecorder` and
`ReportBuilder` consume that stream to build the same durable
`ReportDocument`; direct construction remains a compatibility/testing path.

The same `ReportDocument` feeds JSON, Markdown, console, and
speedscope-compatible renderers. Reports can include `Report.Measurement`
projections, raw samples, derived `Report.Measurement.Row.metrics`, baseline
deltas, single-run budget verdicts, structured verdict causes, source
locations, per-iteration timeline attribution, diagnostic metrics, dimension
curves, and attachments. Unsupported optional diagnostics are represented as
structured `unavailable` states, not as fake zero values.

`Report.Measurement.Metric` is the selector vocabulary for baseline, budget,
and diff checks, for example `.mean`, `.median`, and `.p95`. A
`Report.DimensionCurve` is derived from measurement rows and a selected metric.
The `amortized` field means selected metric divided by
`Benchmark.Dimension.Size.rawValue`.

CLI examples:

```bash
swift package benchmark list --tag fast --format json
swift package benchmark run --tag fast --format json --output report.json
swift package benchmark baseline write --input report.json --output baseline.json
swift package benchmark check --tag fast --baseline baseline.json --baseline-metric p95 --threshold-ns 1000
swift package benchmark diff --input report.json --baseline baseline.json --format json
swift package benchmark trace --tag fast --xctrace-output .build/parser.trace --format json
swift run swift-benchmark-cli run --host .build/debug/ParserBenchmarkHost --case Noop --timeline --format json
```

For ordinary packages, `swift package benchmark` discovers production
benchmark declarations in library targets and generates the runnable host as an
implementation detail. It also discovers supported test-target
`@Suite(.benchmark...)` / `@Test(.benchmark...)` declarations through the
BenchmarkTesting bridge and still runs them through `BenchmarkRunner`.
`--host` is available for advanced/debug flows, executable-only declarations,
or custom host experiments.

## Legacy Signpost Removal

Legacy Signpost public APIs are implementation sources only. They should be
removed from the target public surface during the Instruments migration, not
retained as compatibility APIs.

In the target architecture, Apple Signpost behavior belongs behind
`SignpostRecorder`. User-facing Instruments APIs should describe spans, events,
recorders, tokens, and attributes instead of signpost IDs, signpost intervals,
or subsystem/category wiring.

## Documentation

- `Docs/Architecture/ProductDomains.md`: product-domain map.
- `Docs/Architecture/Instruments.md`: Instruments architecture source of truth.
- `Docs/Architecture/Benchmark.md`: Benchmark architecture source of truth and
  runner scope.
- `Docs/Architecture/Dimension.md`: Dimension-first measurement architecture.
- `Docs/Architecture/Report.md`: Report, baseline, attribution, diagnostics,
  and renderer architecture.
- `Docs/Migrations/Signpost-To-Instruments.md`: migration record.
- `Docs/Reference/InstrumentsAlignmentChecklist.md`: implementation checklist
  for the Instruments alignment pass.
- `Docs/Reference/BenchmarkCompletionChecklist.md`: implementation checklist
  for the Benchmark implementation goal.

## Requirements

Current package settings:

- iOS 18+
- macOS 15+
- Swift tools 6.0+

## License

Dual license:

- `AGPL-3.0-or-later` for open-source use.
- Commercial license for closed-source/proprietary use.

See [LICENSE](./LICENSE) and [COMMERCIAL_LICENSE.md](./COMMERCIAL_LICENSE.md).

## Repository Policy

- Local commit hook path: `.githooks`
- Commit policy CI workflow: `.github/workflows/commit-message.yml`
- Contributor policy: see `CONTRIBUTING.md`.
- Architecture direction: see `Docs/Architecture/Instruments.md`.

- Repository type: `swift-package`.
