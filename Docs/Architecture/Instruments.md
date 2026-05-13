# Instruments Architecture

## Scope / Purpose

This document is the current architecture source of truth for the Instruments
layer of `swift-benchmark`.

For the full product-domain map, see `ProductDomains.md`.

Instruments is runtime-safe instrumentation for production and test code. It
owns spans, events, recorders, timelines, attributes, context, and platform
backends.

The completed Instruments alignment work is scoped to `Instruments`,
`InstrumentsMacros`, and the Apple Signpost backend inside `Instruments`.
That foundation must stay Instruments-first and must not regress into a public
model centered on Signpost as Benchmark and Report consume Instruments data
from outside this layer.

This architecture document describes the complete target shape for the
Instruments layer and keeps the Instruments boundary visible.

At the repository level, Instruments alignment is completed foundation.
Benchmark and Report now consume Instruments data through the implemented
Benchmark/Report scope: Report timeline attribution,
CLI/plugin workflows, adapters, Dimension, Memory/allocation, platform
diagnostics, and Benchmark/Instruments correlation. Those layers may consume
Instruments data, but Benchmark runner behavior and Report policy remain
outside this Instruments layer.

Do not introduce the Benchmark runner, policy objects, report metrics,
baselines, regression gates, Report rendering, XCTest adapters, future
MetricKit adapters, memory benchmarks, Dimension benchmarks, custom Instruments
packages, full OpenTelemetry context propagation, or a full privacy system in
the Instruments alignment layer.

## Context / Boundaries

The public product domain is Instruments. Signpost is not the product domain.

Users should write Instruments semantics:

```swift
#span("BuildIndex") {
  buildIndex()
}

#event("CacheMiss")
```

The package may record those semantics through Apple Signpost, but Signpost is a
backend implementation detail. Public APIs, docs, and macro names should not be
centered around Signpost.

The dependency direction is:

```text
InstrumentsMacros
  -> Instruments runtime APIs
       -> Recorder dispatch
            -> SignpostRecorder / disabled fallback / InMemoryRecorder / CompositeRecorder
```

Macros must not expand directly to `OSSignposter`, `os_signpost`, signpost IDs,
or subsystem/category handling. Apple-specific behavior belongs in
`SignpostRecorder`.

## Unified Upgrade Posture

The current code can be used as a direct refactor base and implementation
source. It is not unusable or throwaway code, but it also should not keep
defining the package's public semantics. The upgrade direction is:

```text
Legacy macro wrapper centered on Signpost
  -> Instruments runtime semantics
  -> Recorder abstraction
  -> SignpostRecorder as Apple backend
  -> Instruments-named macros
```

This was executed as one coherent Instruments upgrade across runtime, macros,
backend isolation, tests, and docs. Legacy Signpost public surfaces are sources
to remove, not compatibility surfaces to preserve.

Before making implementation edits, validate the toolchain and current
implementation constraints: Swift and SwiftSyntax versions, function-body macro
availability, current macro expansion paths, reusable Signpost runtime code,
`Instruments.current` storage safety, `SpanToken` backend requirements, and the
baseline `swift test` result.

## Constraints

- Keep runtime/API code in `Sources/Instruments`.
- Keep macro expansion implementation in `Sources/InstrumentsMacro`.
- Keep changes conservative until the runtime and macro layers are aligned.
- Keep `Recorder` sync-friendly; begin/end/event should be cheap and usable
  from synchronous production code.
- Keep `Span` and `Event` names static where macros receive string literals.
  Dynamic data belongs in attributes.
- Keep Signpost isolated with platform checks so unsupported platforms can still
  compile.
- Keep a disabled or fallback instrumentation path available for unsupported
  platforms, tests, explicit disablement, and release toggles.
- Do not fake attached function instrumentation. `@Instrumented` and `@Span`
  require real function-body macro expansion.
- Treat `@InstrumentedMembers` as macro ergonomics over the same runtime model,
  not as a separate instrumentation backend.

## Current Structure

Current package facts:

- Swift tools version: `6.0`.
- SwiftSyntax dependency: `602.0.0`.
- Public products include `Instruments`, `Benchmark`, `Report`, `Memory`,
  `BenchmarkTesting`, and `BenchmarkXCTest`.
- Runtime/API target: `Sources/Instruments`.
- Macro implementation target: `Sources/InstrumentsMacro`.
- Tests: `Tests/InstrumentsTests`.

Current implementation facts:

- Public APIs are Instruments-first: `#span`, `#event`, `@Span`,
  function-level `@Instrumented`, type/extension-level
  `@InstrumentedMembers`, `Recorder`, `SpanToken`, `SpanAttributes`,
  `Timeline`, `InMemoryRecorder`, `EmptyRecorder`, and `SignpostRecorder`.
- Public Signpost-named macros and the transitional `SignpostMacros` product have
  been removed.
- Macro expansion calls Instruments runtime APIs rather than Apple Signpost APIs.
- `@Span` and function-level `@Instrumented` are real attached body macros.
- `@InstrumentedMembers` is a real member-attribute macro that applies `@Span`
  to eligible methods declared directly in an annotated type or extension.
- Same-name type-level `@Instrumented` is blocked by current Swift macro role
  constraints; this document records the compiler evidence behind the public
  spelling split.

## Unified Upgrade Goals

The implementation pass should align code around these goals:

1. Make the public model Instruments-first across API, docs, examples, product
   naming, and mental model.
2. Make macros call Instruments runtime APIs, not `OSLog`, `OSSignposter`, or
   `os_signpost` directly.
3. Introduce or align a sync-friendly `Recorder` abstraction for spans and
   events.
4. Keep `SpanToken` backend-general and `SpanAttributes` small, sendable, and
   suited to small dynamic metadata.
5. Provide a cheap disabled/fallback instrumentation path.
6. Default Apple platforms to `SignpostRecorder` where feasible.
7. Keep non-Apple and unsupported platforms compiling with fallback behavior.
8. Preserve the Timeline/InMemory direction inside Instruments, not Report.
9. Preserve a nested-span/context direction without building full distributed
   tracing.
10. Keep span and event names stable `StaticString` values where macros receive
    literals; put dynamic context in attributes.
11. Ensure every successful span begin is ended exactly once on success, thrown
    error, and cancellation paths where `defer` runs.
12. Support `@Span` as the function-level body macro, function-level
    `@Instrumented` as ergonomic syntax over the same span semantics, and
    `@InstrumentedMembers` as type/extension bulk member instrumentation.
13. Do not introduce Benchmark runner behavior in this Instruments layer.

## Current-To-Target Status

| Area | Current state | Target state |
| --- | --- | --- |
| Public model | Instruments-first APIs are implemented. | Keep public semantics centered on Instruments. |
| Runtime | `Recorder`, `SpanToken`, `SpanAttributes`, `Instruments.current`, fallback, and timeline are implemented. | Continue keeping runtime sync-friendly and backend-general. |
| Backend | `SignpostRecorder` owns Apple Signpost behavior. | Keep Apple-specific APIs isolated behind the backend. |
| Macros | `#span`, `#event`, `@Span`, function-level `@Instrumented`, and `@InstrumentedMembers` are implemented. | Preserve the spelling split until the Swift macro role model supports one same-name macro for function and type attachment. |
| Disabled path | `EmptyRecorder` is implemented. | Keep unsupported/disabled paths cheap. |
| Timeline | `Timeline` / `InMemoryRecorder` are implemented. | Later Benchmark/Report integration consumes public timeline snapshots. |
| Docs | README, architecture docs, migration docs, and tests describe implemented status plus the same-name type-level macro blocker. | Keep architecture truth current. |

## Target Runtime Model

The Instruments layer owns these concepts:

- `Span`: a duration-bearing operation.
- `Event`: a point-in-time marker.
- `Recorder`: the synchronous runtime recording protocol.
- `SpanToken`: an opaque token returned by `beginSpan` and consumed by
  `endSpan`.
- `SpanAttributes`: lightweight sendable dynamic metadata.
- `Timeline`: captured span/event records for in-process inspection and future
  benchmark/report integration.
- `Instruments`: the runtime entry point, including the current recorder.
- `Recorders`: concrete recorder implementations.
- Disabled/fallback instrumentation: a cheap, safe no-op path for unsupported
  platforms and explicit disablement.

Preferred long-term layout:

```text
Sources/
  Instruments/
    Span.swift
    Event.swift
    Recorder.swift
    SpanToken.swift
    SpanAttributes.swift
    Timeline.swift
    Instruments.swift
    Recorders/
      EmptyRecorder.swift
      InMemoryRecorder.swift
      CompositeRecorder.swift
      SignpostRecorder.swift
  InstrumentsMacros/
    SpanMacro.swift
    EventMacro.swift
    InstrumentedMacro.swift
    AttachedSpanMacro.swift
```

The current target name is `InstrumentsMacro`, not `InstrumentsMacros`. Prefer
aligning behavior before broad target/file renames.

## Key Principles

### Runtime API

The runtime surface should be sync-friendly and `Sendable`:

```swift
public protocol Recorder: Sendable {
  func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken
  func endSpan(_ token: SpanToken)
  func recordEvent(_ name: StaticString, attributes: SpanAttributes)
}
```

Convenience APIs can layer on the protocol:

```swift
public extension Recorder {
  func span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ operation: () throws -> T
  ) rethrows -> T

  func event(
    _ name: StaticString,
    attributes: SpanAttributes = .empty
  )
}
```

Async overloads are desirable when they can be implemented cleanly.

### Current Recorder

`Instruments.current` should provide a sync-friendly current recorder:

```swift
public enum Instruments {
  public static var current: Recorder { get set }
}
```

Do not implement it as an unsafe unsynchronized mutable global. Preferred
options are locked process-wide storage, `TaskLocal` override plus locked
default storage, or a small synchronized box.

On supported Apple platforms, `Instruments.current` should default to
`SignpostRecorder` unless the package has a strong reason to default to disabled
instrumentation. Unsupported platforms should default to the disabled/fallback
path unless `InMemoryRecorder` is explicitly configured.

### SpanToken

`SpanToken` must represent backend-specific state without making Signpost the
only possible backend.

Requirements:

- can carry or reference a Signpost interval state for `SignpostRecorder`,
- can carry child tokens for `CompositeRecorder`,
- can represent an inert token for `EmptyRecorder`,
- can support exactly-once ending where a recorder needs that guarantee,
- remains `Sendable`.

Do not model `SpanToken` as a raw `OSSignpostIntervalState`.

### Attributes and Names

`SpanAttributes` are dynamic metadata. Span and event names identify stable
semantic operations; attributes carry contextual values.

Accepted scope:

- `Sendable` storage,
- `.empty`,
- dictionary literal support if straightforward,
- scalar values such as `String`, `Int`, `Double`, `Bool`, and `UUID`,
- optional string-convertible fallback if needed.

Do not build a full OpenTelemetry-style attribute system in the Instruments
alignment pass.

Span and event names should be stable operation identities, such as
`"BuildIndex"`, `"ParseDocuments"`, `"CacheMiss"`, or
`"RemoteSearchCompleted"`. Avoid names containing runtime IDs, timestamps, file
paths, user data, or large interpolated values. Dynamic context belongs in
`SpanAttributes`.

## Recorder Backends

### Disabled / Fallback Path

A disabled/fallback instrumentation path must exist. It does not have to be a
public type named `EmptyRecorder`.

Acceptable implementations include:

- internal `EmptyRecorder`,
- internal `DisabledRecorder`,
- `Instruments.disabled`,
- compile-time disabled path,
- unsupported-platform fallback.

The disabled path should be cheap and safe. Where feasible, structure it so the
compiler can optimize disabled instrumentation away.

If an `EmptyRecorder` type is implemented, it should:

- compiles on every supported platform,
- is `Sendable`,
- returns inert valid `SpanToken` values,
- makes begin/end/event no-ops.

### SignpostRecorder

`SignpostRecorder` is the Apple backend.

It maps:

- `Span` to an `OSSignposter` interval,
- `Event` to an `OSSignposter` event.

Rules:

- isolate Apple imports and APIs with `#if canImport(OSLog)` or equivalent platform
  checks,
- keep unsupported platforms compiling,
- prefer `OSSignposter`,
- use legacy `os_signpost` only as an internal backend fallback if the
  implementation needs it; do not expose its shape publicly,
- do not let legacy API shape define the public Instruments API,
- do not default to `.exclusive` for spans that may overlap,
- generate independent signpost IDs where concurrent, nested, async, or
  benchmark-related spans can overlap,
- retain begin interval state inside the token/recorder model and pass it to
  `endSpan`,
- compile cleanly on unsupported platforms by being unavailable, stubbed, or
  internally disabled.

### InMemoryRecorder

`InMemoryRecorder` belongs to Instruments, not Report. It records runtime facts;
Report later renders or aggregates them.

Expected records:

- span begin,
- span end,
- event,
- timestamp or monotonic time,
- attributes,
- optional parent/span identity.

Snapshot/reset support is useful for future Benchmark integration:

```text
configure InMemoryRecorder
  -> run workload
  -> snapshot Timeline
  -> reset recorder
  -> run next sample
```

It does not need aggregation, Report metrics, or CI output.

### CompositeRecorder

`CompositeRecorder` is an extension point for fan-out recording. If implemented,
`beginSpan` must return a token that can end all child recorder spans exactly
once. It requires a future accepted architecture change before becoming public
surface.

## Macro Surface

The desired public macro surface is:

```swift
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

```

Do not add new public APIs named `#signpost`, `@Signpost`, or `@Signposted`.
Existing Signpost-named macros are transitional implementation sources to remove
from the target public surface.

Macro priority:

- `#span` and `#event`.
- `@Span("Name")` using real body macro expansion.
- `@Instrumented` on functions as a semantic alias over `@Span`.
- `@Instrumented` on types as bulk member instrumentation over `@Span` remains
  blocked by current Swift macro role constraints.

### `#span`

`#span` records a duration and should preserve:

- sync and throwing bodies,
- async and async throwing bodies when supported,
- return values,
- nested spans,
- error paths through `defer`-based cleanup,
- cancellation paths where `defer` runs.

Conceptual expansion:

```swift
try await Instruments.current.span("BuildIndex") {
  try await buildIndex()
}
```

or, when necessary:

```swift
let token = Instruments.current.beginSpan("BuildIndex", attributes: .empty)
defer { Instruments.current.endSpan(token) }
```

### `#event`

`#event` records a single point-in-time marker:

```swift
Instruments.current.recordEvent("CacheMiss", attributes: .empty)
```

It must not create a span token or duration record.

### `@Span`

`@Span` is the function-level attached body macro. It wraps the existing function
body in a `beginSpan` / `endSpan` pair and preserves the original declaration
shape.

Conceptual expansion:

```swift
@Span("BuildIndex")
func buildIndex() throws -> Index {
  try build()
}
```

becomes:

```swift
func buildIndex() throws -> Index {
  let token = Instruments.current.beginSpan("BuildIndex", attributes: .empty)
  defer { Instruments.current.endSpan(token) }
  try build()
}
```

The macro must preserve access control, generics, attributes, async/throws/
rethrows, return values, and where clauses. It must not swallow, transform, or
mask user errors.

When no explicit name is provided, default span names should be stable
`StaticString` operation identities:

- `functionName` for free functions,
- `TypeName.methodName` for methods where type context is available.

Dynamic values belong in `SpanAttributes`, not in the span name.

### `@Instrumented`

`@Instrumented` is ergonomic syntax over `@Span`, not a separate runtime model.

On a function, `@Instrumented` behaves like `@Span` with the default stable span
name:

```swift
@Instrumented
func openProject() async throws -> Project {
  ...
}
```

For a nominal type or extension, the implemented bulk instrumentation spelling is
`@InstrumentedMembers`. It applies `@Span` to eligible methods in that
declaration body, then lets `@Span` perform the body rewrite:

```swift
@InstrumentedMembers
struct Store {
  func load() async throws -> Item { ... }
  static func warmCache() throws { ... }
}
```

is semantically equivalent to:

```swift
struct Store {
  @Span("Store.load")
  func load() async throws -> Item { ... }

  @Span("Store.warmCache")
  static func warmCache() throws { ... }
}
```

`@InstrumentedMembers` rules:

- instrument methods declared directly in the annotated type or extension body,
- do not automatically instrument methods in separate extensions unless that
  extension is also annotated,
- do not instrument protocol requirements without bodies,
- do not implicitly instrument properties, property accessors, `init`, or
  `deinit` unless a later architecture decision explicitly extends the macro
  surface,
- preserve member access control and declaration attributes,
- use stable `TypeName.methodName` span names.

Current implementation note: the local Swift macro system rejects a single
public `@Instrumented` macro declaration that combines function `body` and type
`memberAttribute` roles, and it also rejects duplicate `Instrumented()` macro
declarations with separate roles. Function-level `@Instrumented` is implemented;
type/extension bulk instrumentation is implemented as `@InstrumentedMembers`.
Do not reintroduce fake same-name type-level instrumentation.

Attached function instrumentation requires real function-body macro expansion.
Do not ship attached macros that compile but do not instrument the function body.

Before implementing them, verify:

- Swift tools version,
- SwiftSyntax version,
- attached body macro role availability,
- plugin registration support,
- preservation of access control, generics, attributes, async/throws/rethrows,
  return values, and where clauses.

Run a body macro smoke test before implementing them in the package. The smoke
test verifies implementation mechanics; it is not a new architecture decision.

## Cross-cutting Concerns

### Timeline Boundary

`Timeline` is an Instruments concept because Instruments records runtime
spans/events. Report consumes timeline data through optional attribution
adapters.

Completed optional flow:

```text
Benchmark runner
  -> repeatedly runs workload
  -> workload emits spans/events
  -> InMemoryRecorder collects timeline
  -> Report aggregates per-span metrics
```

Do not implement benchmark aggregation in the Instruments alignment layer.

### Nested Span Context

The runtime should preserve a path for nested spans and parent-child
relationships:

```text
BuildIndex
  ParseDocuments
  ResolveSymbols
  EmitIndex
```

Acceptable designs include `TaskLocal` current span context,
recorder-owned span stacks, parent span IDs, or backend-owned IDs. Do not build
a full distributed tracing system in this pass.

### Error and Cancellation Safety

A span must end exactly once for every successful begin. Thrown errors and
cancellation paths must not skip `endSpan`. Prefer `defer`-based cleanup, and do
not swallow, transform, or mask user errors. If error recording is added, record
error information as attributes or a terminal event.

### Timing

For span duration and timeline timing, prefer a monotonic time source where
available. Do not rely on wall-clock `Date` as the primary duration source
unless no better option is practical. Wall-clock time may be stored as optional
metadata.

### Attribute Discipline

Attributes should be small, `Sendable`, and suitable for runtime
instrumentation. Avoid arbitrary object capture, large payloads, file contents,
user data, and expensive stringification by default. If privacy is not already
modeled in the repo, leave it as a documented future extension rather than
building a broad privacy system in this pass.

### Platform Availability

The package currently targets macOS 15 and iOS 18. The Signpost backend should
remain isolated so non-Apple or unsupported platforms can use `EmptyRecorder` and
compile the Instruments runtime where the package later chooses to support them.

Signpost-specific implementation must be isolated with platform checks such as:

```swift
#if canImport(os)
import os
#endif
```

### SwiftPM Workflow

This is a SwiftPM-first package. Use `Package.swift` as the source of truth for
products, targets, executable products, and plugins. Validate implementation
passes with `swift build` and `swift test` unless a narrower command is
justified.

The Instruments layer is a library/runtime layer. Executable and plugin
products belong to the CLI/plugin workflow and must not move Benchmark runner
or Report policy into Instruments.

## Risks / Extension Points

- Same-name type-level `@Instrumented` is blocked by current Swift macro
  attachment-role constraints; `@InstrumentedMembers` is the accepted
  implemented bulk instrumentation spelling for this pass.
- `CompositeRecorder` remains an extension point and is not part of the current
  implementation.
- Report, baseline/regression, CLI/plugin, Testing/XCTest adapters, Dimension,
  Memory, future MetricKit, and custom Instruments integration are separate
  product layers over Benchmark/Report. They may consume Instruments data, but
  they do not belong in the Instruments runtime layer.

## Code Upgrade Guidance

Implementation status for the unified implementation pass:

0. Run the pre-implementation validation: inspect package/target names, current
   Signpost-named APIs, macro expansion files, direct Apple API calls, reusable
   Signpost runtime code, Swift/SwiftSyntax versions, body macro availability,
   `Instruments.current` storage options, `SpanToken` requirements, and the
   baseline `swift test` result.
1. Runtime types, current recorder storage, and fallback path are implemented.
2. Apple platforms default through `SignpostRecorder` where OSLog is available.
3. Signpost-specific behavior is behind `SignpostRecorder`.
4. `#span` and `#event` expand to Instruments runtime APIs.
5. Signpost-named public macros and transitional Signpost-facing surfaces are
   removed.
6. `@Span` and function-level `@Instrumented` use real function-body macro
   expansion; `@InstrumentedMembers` uses real member-attribute expansion to
   apply `@Span` to eligible methods.
7. `Timeline` and `InMemoryRecorder` are implemented.
8. Tests are Instruments-first.
9. Benchmark core and the first Report product layer are implemented as
   separate layers. Deep Report diagnostics remain outside Instruments runtime.

## Architecture Documentation Guidance

Update architecture docs in the same pass as code changes:

1. Keep this file as the current Instruments architecture truth.
2. Update `ProductDomains.md` if public products, transitional modules, or
   adapter/diagnostics boundaries change.
3. Update `../Migrations/Signpost-To-Instruments.md` with the actual migration
   outcome and removed Signpost surface.
4. Keep `../Reference/InstrumentsAlignmentChecklist.md` as implementation
   checklist/reference material, not accepted architecture truth.
5. Keep root `README.md` aligned with available target APIs.

## Related Decisions

Preflight decisions live in `../Decisions/Preflight-Implementation-Decisions.md`.
If a later pass changes target names or the accepted macro scope, record that
history under `Docs/Decisions/` and restate current truth here.
