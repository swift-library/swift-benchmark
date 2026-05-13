# Preflight Implementation Decisions

Status: Accepted

Date: 2026-05-10

## Context

Before implementing the Instruments and Benchmark targets, resolve
the decisions that would otherwise interrupt execution. After these decisions
are recorded, implementation should follow the accepted architecture and
reference checklists. Stop only for toolchain facts that invalidate these
decisions, architecture contradictions, or product-boundary violations.

Local package facts at decision time:

- Swift tools version: `6.0`.
- Local Swift toolchain: `Apple Swift version 6.3.1`.
- SwiftSyntax dependency: `602.0.0`.
- Current public products: `Instruments` and transitional `SignpostMacros`.
- Current targets: `Instruments`, `InstrumentsMacro`,
  `SignpostMacrosCompat`, and `InstrumentsTests`.
- SwiftSyntax includes `BodyMacro` and SwiftSyntax tests show body replacement can
  work for declarations with existing bodies.

Implementation order:

1. Complete Instruments.
2. Complete Benchmark.

The accepted architecture and reference checklists must cover the whole
implementation, not only the first slice.

## Product And Target Decisions

- Keep the existing `Instruments` product and target.
- Keep the existing `InstrumentsMacro` target name during behavior alignment.
  Rename only if a future accepted architecture change schedules the
  file/target move.
- Remove the `SignpostMacros` compatibility product and
  `SignpostMacrosCompat` target during the Instruments migration. Do not retain
  legacy Signpost-named public APIs as compatibility surfaces.
- Add a new `Benchmark` library product and `Benchmark` target for Benchmark
  runtime code.
- Add a new `BenchmarkTests` test target for Benchmark tests.
- Do not put Benchmark runner code in `Sources/Instruments`.

## Instruments Decisions

- The target public runtime model is `Recorder`, `SpanToken`,
  `SpanAttributes`, `Instruments.current`, `EmptyRecorder`,
  `SignpostRecorder`, `InMemoryRecorder`, and `Timeline`.
- `CompositeRecorder` remains a future-compatible direction unless it stays
  small enough to implement without broadening `SpanToken` unnecessarily.
- Existing Signpost-oriented runtime and macro code is a usable refactor base.
  Move reusable behavior behind `SignpostRecorder` instead of rewriting from
  scratch.
- `SignpostRecorder` is the Apple backend and owns all `OSSignposter`,
  `os_signpost`, signpost ID, subsystem/category, and interval-state behavior.
- Apple-supported platforms should default to `SignpostRecorder` where
  feasible. Unsupported platforms and explicit disablement use
  `EmptyRecorder`.
- `Instruments.current` must use concurrency-safe storage. Use a small locked
  process-wide default recorder box first. Do not use an unsafe unsynchronized
  mutable global. Task-local overrides can be added later if needed.
- `SpanToken` should be an opaque `Sendable` public value with internal
  backend-specific storage for empty tokens, Signpost interval state, and future
  composite child tokens.
- `SpanAttributes` should be a small `Sendable` attribute container with
  `.empty` and scalar values. Do not implement a full tracing attribute system
  in the Instruments pass.
- Implement `#span` and `#event` as the primary macro surface.
- `#span` expands to Instruments runtime APIs and uses defer-style cleanup so a
  successfully begun span ends exactly once.
- `#event` expands to exactly one runtime event call and must not create a span
  token or duration record.
- Implement `@Instrumented`, `@InstrumentedMembers`, and `@Span` as part of the
  Instruments target using real macro expansion. Run a preflight macro smoke
  test as verification, not as a new design decision. Do not ship fake attached
  macros.
- `@Span` is the function-level body macro. `@Instrumented` on a function is
  ergonomic syntax over the same span semantics with a default stable name.
- Same-name type-level `@Instrumented` was the desired spelling, but Swift
  6.3.1 rejects one public macro declaration that combines function `body` and
  type `memberAttribute` roles and also rejects duplicate same-name declarations
  with separate roles.
- `@InstrumentedMembers` is the accepted implemented spelling for nominal type
  or extension bulk instrumentation. It applies span instrumentation to eligible
  member functions in that declaration body and is not a separate runtime model.
- `@InstrumentedMembers` does not automatically instrument separate
  extensions, protocol requirements without bodies, properties, property
  accessors, `init`, or `deinit` unless a later decision extends the macro
  surface.
- Remove legacy Signpost-named public APIs from the target public surface.
  Reusable implementation code may remain internally only behind
  `SignpostRecorder`.

## Benchmark Decisions

- Public naming set:
  `BenchmarkSuite`, `BenchmarkCase` / `Benchmark`, `BenchmarkRunner`,
  `BenchmarkConfiguration`, `WarmupPolicy`, `IterationPolicy`, `Sample`,
  `Measurement`, `BenchmarkResult`, and `blackHole`.
- Use `BenchmarkCase` as the canonical stored workload type.
- Use `Benchmark` as the public authoring name. Prefer
  `public typealias Benchmark = BenchmarkCase` if it compiles cleanly; otherwise
  use a small `Benchmark(...) -> BenchmarkCase` factory.
  - Typealias means `Benchmark("Name") { ... }` is the `BenchmarkCase`
    initializer exposed through the shorter authoring name.
  - Factory means an uppercase `Benchmark(...)` function returns a
    `BenchmarkCase` if typealias overloads do not stay clean.
- Store operations internally as `@Sendable () async throws -> Void`.
- Provide initializers or wrappers for sync, throwing, async, and async
  throwing workloads.
- Non-`Void` operation overloads should route returned values through
  `blackHole`; manual `blackHole(...)` remains valid.
- `BenchmarkRunner.run` should be an async throwing API returning
  `[BenchmarkResult]`.
- If a benchmark operation throws, fail visibly with suite/case/phase context
  rather than converting the failure into a sample. A future run wrapper can add
  partial-result reporting if needed.
- Use a small `BenchmarkClock` abstraction over monotonic time, backed by
  `ContinuousClock` by default and injectable in tests.
- `WarmupPolicy` supports `.none` and `.iterations(Int)`.
- `IterationPolicy` supports `.iterations(Int)`.
- Default warmup is `.iterations(1)`.
- Default measured iterations are `.iterations(10)`.
- Validate configuration before execution: warmup count must be nonnegative and
  measured iteration count must be positive.
- Runner execution is deterministic and serial by default; parallel execution
  requires a future accepted architecture change.
- Preserve raw `Sample` values as the truth. Derive `Measurement` and
  `BenchmarkResult` from those samples; Report derives metrics.
- Use accepted implementation patterns where they fit local boundaries:
  `blackHole`, metrics calculation, raw sample preservation, runner
  warmup/measurement/result flow, and Signpost begin/end pairing. Keep any
  copied code subject to licensing/provenance review.
- Capture baseline, CI gate, SwiftPM command plugin, Report rendering, Swift
  Testing adapter, XCTest adapter, Dimension/report curves,
  Memory/allocation metrics, and Instruments timeline aggregation as separate
  product layers. Do not collapse them into the core Benchmark runner
  semantics.
- Swift Testing traits are adapters over Benchmark core. They must not
  replace `BenchmarkSuite`, `BenchmarkCase`, `BenchmarkRunner`, raw samples,
  `Benchmark.Measurement`, or structured results.

## Execution Rule

Implementation should follow these accepted decisions and the architecture
truth. Do not pause for ordinary local design choices that these decisions
already cover. Pause only when a toolchain fact invalidates a decision, accepted
architecture documents conflict, or the implementation would cross product
boundaries.
