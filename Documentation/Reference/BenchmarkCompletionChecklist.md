# Benchmark Completion Checklist

Use this checklist when implementing or auditing the Benchmark product goal. It
supports the architecture in `Documentation/Architecture/Benchmark.md`.

This checklist is secondary to `Documentation/Architecture/ImplementationScope.md`
for the active closure. If this file conflicts with that
document, update this file rather than reopening the accepted architecture.

## Scope

This target is about completing the Benchmark product layer by implementing the
accepted architecture direction:

- Benchmark declarations,
- benchmark suite and benchmark case model,
- benchmark runner,
- warmup,
- measured iterations,
- samples,
- measurement rows,
- structured results,
- Dimension rows,
- architecture-defined extension points,
- focused tests and README updates.

Keep these concerns in their own product/adaptor boundaries:

- baselines and CI regression gates, owned by Report/CLI/adapters,
- SwiftPM command plugin and CLI workflow,
- Report structured output and optional rendering/export consumers,
- Swift Testing adapter,
- XCTest adapter,
- Report Dimension curves,
- Memory/allocation metrics,
- Instruments timeline aggregation.

Benchmark may be implemented in the same coordinated effort as Instruments, but
it must remain its own product layer. Do not put the Benchmark runner inside
Instruments runtime or macro code. Use this checklist to keep the target
complete while architecture and reference docs retain durable truth.

## Required Inspection Before Editing

Verify these before implementation. The accepted answers are recorded in
`../Decisions/PreflightImplementationDecisions.md`; these checks should not
reopen the architecture unless local facts contradict that decision record.

1. Verify current package facts still match architecture docs after the
   implementation pass: products `Instruments`, `Benchmark`, `Report`,
   `Memory`, `BenchmarkTesting`, `BenchmarkXCTest`, executable
   `BenchmarkCLI`, and plugin `BenchmarkPlugin`.
2. Keep the `Benchmark` product and `Benchmark` target independent from
   Instruments internals.
3. Keep `BenchmarkTests` focused on Benchmark behavior.
4. Reuse only isolated Benchmark helpers or accepted algorithms; do not reuse or
   depend on Instruments internals.
5. Use `BenchmarkClock` over `ContinuousClock` for monotonic wall-clock
   measurement, with test injection.
6. Preserve thrown errors by failing visibly with suite/case/phase context.
7. Keep the public API to suite/case declaration, configuration, serial runner
   execution, raw samples, measurement rows, and structured results.
8. Implement `blackHole` in the Benchmark core
   and keep unsafe/compiler-sensitive details isolated.

## Pre-Implementation Decisions

Follow these accepted decisions before changing Benchmark package structure or
runtime behavior:

- Read `../Decisions/PreflightImplementationDecisions.md`.
- Product and target names.
- Public naming set:
  `BenchmarkSuite`, `BenchmarkCase` / `Benchmark`, `BenchmarkRunner`,
  `BenchmarkConfiguration`, `WarmupPolicy`, `IterationPolicy`, `Sample`,
  `Measurement`, `BenchmarkResult`, and `blackHole`.
- Whether `Benchmark` is a `BenchmarkCase` typealias, factory, or initializer
  surface.
  Prefer `public typealias Benchmark = BenchmarkCase`: this lets users write
  `Benchmark("Name") { ... }` while keeping `BenchmarkCase` as the stored model.
  Use an uppercase `Benchmark(...) -> BenchmarkCase` factory only if typealias
  overloads do not stay clean.
- Operation normalization shape for sync, throwing, async, and async throwing
  workloads.
- Runner error model for thrown benchmark operations.
- Clock source and whether a test clock abstraction is needed.
- Warmup and measured iteration policy semantics.
- Which accepted code/algorithms are used directly.
- Which accepted lessons remain extension seams rather than core runner
  behavior.

After these decisions are recorded, continue without pausing for ordinary local
design choices. Stop only for toolchain facts that invalidate accepted
decisions, architecture contradictions, or product-boundary violations.

## Completion Goals

1. Add a Benchmark product boundary without coupling it to Instruments
   internals.
2. Provide a canonical suite and case model.
3. Provide a result-builder declaration layer over the canonical model.
4. Implement a deterministic serial runner.
5. Support warmup and measured iterations.
6. Measure wall-clock duration with a monotonic source where practical.
7. Preserve thrown errors instead of converting failures into silent samples.
8. Store raw samples and measurement rows; Report derives metrics.
9. Return structured results suitable for future Report consumption.
10. Keep baseline, CI, adapter, Dimension, memory, and Report capabilities in
    extension seams without collapsing those domains into the core runner.
11. Keep Swift Testing traits as adapters over Benchmark core, not as the core
    benchmark execution model.

## Model Checklist

Expected concepts:

```text
BenchmarkSuite
BenchmarkCase / Benchmark
BenchmarkRunner
BenchmarkConfiguration
WarmupPolicy
IterationPolicy
Sample
Measurement
BenchmarkResult
```

The exact type signatures can follow implementation needs, but the model should
keep declaration, execution, raw samples, Measurement rows, Report-derived
metrics, and structured results separate.

## Runner Checklist

The runner should:

- execute cases serially,
- perform warmup before measured iterations,
- run a fixed number of measured iterations,
- collect one sample per measured iteration,
- preserve case identity in results,
- propagate or report thrown errors explicitly,
- avoid baseline comparison and regression decisions,
- avoid dependency on Swift Testing or XCTest.

## Test Matrix

Run:

```bash
swift build
swift test
```

Verify or add tests for:

- declaring an empty suite,
- declaring a suite with one case,
- declaring a suite with multiple cases,
- runner executes each measured iteration,
- warmup runs before measurement and is not counted as a measured sample,
- thrown errors are preserved,
- sample count matches fixed iteration configuration,
- Measurement rows preserve samples,
- structured result contains suite and case identity,
- Benchmark target does not depend on Instruments internals.

## Final Report Template

Implementation passes should report:

1. Phase / stage judgment.
2. Files changed.
3. What changed, separated by declaration model, runner, configuration,
   samples/measurements/results, docs, and tests.
4. Why it changed.
5. Impact / scope.
6. Tests / validation.
7. Recommended next steps.

Explicitly answer:

- Is there a public Benchmark product?
- Is there a real runner?
- Are warmup and measured iterations implemented?
- Are samples and Measurement rows implemented?
- Are structured results implemented?
- Did Benchmark depend on Instruments internals?
- Was any Report, baseline, CI gate, adapter, Dimension, or memory work
  introduced?
