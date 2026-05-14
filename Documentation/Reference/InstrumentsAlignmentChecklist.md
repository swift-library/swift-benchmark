# Instruments Alignment Checklist

Use this checklist when implementing the first Instruments alignment pass. It is
implementation reference material that supports the current architecture in
`Documentation/Architecture/Instruments.md`.

This checklist covers the Instruments target only. The repository completion
goal also includes the Benchmark target, covered by
`BenchmarkCompletionChecklist.md`.

## Scope

This pass is only about:

- `Instruments`,
- `InstrumentsMacros`,
- the Apple Signpost backend inside `Instruments`.

Do not implement:

- `BenchmarkRunner`,
- `WarmupPolicy`,
- `IterationPolicy`,
- `SamplePolicy`,
- Report-derived metrics,
- baselines,
- regression gates,
- CI reports,
- Report rendering,
- XCTest adapters,
- MetricKit adapters,
- memory benchmarks,
- Dimension benchmarks,
- custom Instruments packages,
- full OpenTelemetry context propagation,
- full privacy system.

## Required Inspection Before Editing

These checks are required before implementation edits. Do not start by
rewriting the current Instruments code; inspect it first and refactor the usable
parts directly.

Collect these facts before implementation. The architecture is already accepted
in `../Decisions/PreflightImplementationDecisions.md`; these checks only
pause execution if local facts contradict that decision record:

1. What are the current package, product, and target names?
2. Which APIs are currently Signpost-named?
3. Which files implement the current macro expansion?
4. Does macro expansion directly call `OSSignposter` or `os_signpost`?
5. Which code can be reused as `SignpostRecorder`?
6. Is there already a runtime abstraction, or is the macro directly tied to
   Signpost?
7. What Swift compiler and SwiftSyntax versions are used?
8. Are function-body macros available and configured?
9. What direct breaking cleanup is required to align the package around
   Instruments?

## Pre-Implementation Validation

Complete and record these before changing runtime or macro behavior:

- Read `../Decisions/PreflightImplementationDecisions.md`.
- Run a baseline `swift test`.
- Confirm Swift compiler and SwiftSyntax versions from `Package.swift` and the
  local toolchain.
- Verify whether attached function-body macros are actually available and
  registered for this package.
- Identify every macro expansion path that directly calls `OSSignposter`,
  `os_signpost`, or Signpost-oriented runtime helpers.
- Identify current Instruments runtime files that can move directly into
  `SignpostRecorder`.
- Decide the concurrency-safe storage strategy for `Instruments.current`.
- Decide the `SpanToken` representation for Signpost interval state,
  `EmptyRecorder`, and future `CompositeRecorder`.
- Remove legacy Signpost-named public APIs during the pass.

After these decisions are recorded, continue without pausing for ordinary local
design choices. Stop only for toolchain facts that invalidate accepted
decisions, architecture contradictions, or product-boundary violations.

## Implementation Goals

1. Public API, docs, examples, product naming, and mental model are
   Instruments-first.
2. Macros call Instruments runtime APIs, not `OSLog`, `OSSignposter`, or
   `os_signpost`.
3. A sync-friendly `Recorder` abstraction dispatches spans and events.
4. `SpanToken` is backend-general and `SpanAttributes` is small and sendable.
5. A cheap disabled/fallback instrumentation path exists.
6. Apple platforms default to `SignpostRecorder` where feasible.
7. Non-Apple and unsupported platforms compile with fallback behavior.
8. Timeline and `InMemoryRecorder` remain Instruments concepts.
9. Nested span and parent-child context direction is preserved.
10. Names are stable `StaticString` operation names; dynamic context is stored
    in attributes.
11. Spans end exactly once across success, thrown error, and cancellation paths
    where `defer` runs.
12. No Benchmark runner behavior is introduced.

## Runtime Checklist

Runtime surface:

```swift
public protocol Recorder: Sendable {
  func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken
  func endSpan(_ token: SpanToken)
  func recordEvent(_ name: StaticString, attributes: SpanAttributes)
}

public struct SpanToken: Sendable { ... }

public struct SpanAttributes: Sendable { ... }

public enum Instruments {
  public static var current: Recorder { get set }
}
```

Convenience APIs may be added:

```swift
public extension Recorder {
  func span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = [:],
    _ operation: () throws -> T
  ) rethrows -> T

  func event(
    _ name: StaticString,
    attributes: SpanAttributes = [:]
  )
}
```

Keep `Recorder` usable from sync and async call sites. Do not make recorder
methods async-only. Synchronize mutable concrete recorders internally.

## Macro Checklist

- `#span`
- `#event`
- `@Instrumented`
- `@InstrumentedMembers`
- `@Span("Name")`

Do not ship attached macros that compile but do not instrument the function
body.

Macro semantics to verify:

- `@Span` wraps function bodies with begin/end span cleanup.
- Function-level `@Instrumented` behaves like `@Span` with a default stable
  name.
- `@InstrumentedMembers` applies span instrumentation to eligible member
  functions in the annotated type or extension body.
- `@InstrumentedMembers` does not silently instrument separate extensions,
  protocol requirements without bodies, properties, property accessors, `init`,
  or `deinit`.
- Generated names use stable `StaticString` operation identities such as
  `functionName` or `TypeName.methodName`.

`#span` must preserve or explicitly document gaps for:

- sync closures,
- throwing closures,
- async closures,
- async throwing closures,
- return values,
- nested spans,
- thrown errors ending spans,
- cancellation paths where `defer`-based cleanup applies.

`#event` must emit exactly one runtime event call, create no span token, and
record no duration.

## Signpost Backend Checklist

`SignpostRecorder` is the Apple backend. It maps:

- `Span` to `OSSignposter` interval,
- `Event` to `OSSignposter` event.

Rules:

- isolate Apple-specific implementation behind platform checks,
- use `#if canImport(os)`,
- prefer `OSSignposter`,
- use legacy `os_signpost` only as an internal backend fallback if needed,
- do not let legacy API shape define public Instruments API,
- do not default to `.exclusive` for overlapping spans,
- generate independent signpost IDs where nested, async, parallel, or
  benchmark-related spans can overlap,
- preserve begin/end pairing through `SpanToken` or backend-owned state,
- compile cleanly on unsupported platforms with fallback behavior.

## Timeline / InMemory Checklist

`Timeline` direction:

```text
Timeline
  SpanRecord
    id
    parentID?
    name
    start
    end
    attributes
  EventRecord
    id
    parentSpanID?
    name
    timestamp
    attributes
```

`InMemoryRecorder` direction:

- record span begin,
- record span end,
- record event,
- store monotonic timestamps where available,
- store attributes,
- consider snapshot/reset support.

Do not implement benchmark Report metrics or aggregation.

## Test Matrix

Run:

```bash
swift build
swift test
```

For `#span`, verify or add tests for:

- sync non-throwing body,
- sync throwing body,
- async body,
- async throwing body,
- return value preservation,
- nested `#span` calls,
- thrown error still ends span.

For `#event`, verify:

- exactly one runtime event call,
- no duration/span token,
- attributes passed when supported.

For `@Instrumented`, `@InstrumentedMembers`, and `@Span`, verify:

- access control preserved,
- `async`, `throws`, and `rethrows` preserved,
- return type preserved,
- generics and where clauses preserved,
- function attributes not dropped,
- body wrapped exactly once,
- thrown errors still end span,
- return values preserved.
- member instrumentation skips ineligible declarations and already-instrumented
  methods.

## Final Report Template

Implementation passes should report:

1. Phase / stage judgment.
2. Files changed.
3. What changed, separated by runtime, macros, Signpost backend,
   disabled/fallback path, timeline/InMemory direction, and docs/tests.
4. Why it changed.
5. Impact / scope.
6. Code diff key hunks.
7. Tests / validation.
8. Recommended next steps.

Explicitly answer:

- Is Signpost still a top-level public concept?
- Do macros call Instruments runtime, or Apple Signpost directly?
- Is `SignpostRecorder` now a backend?
- Does the package compile cross-platform?
- Are `#span` and `#event` implemented?
- Are `@Instrumented` and `@Span` implemented with real body expansion?
- Is there a disabled/fallback instrumentation path?
- Does Apple platform default to `SignpostRecorder`?
- Is `InMemoryRecorder` implemented?
- Is `Timeline` implemented?
- Was any Benchmark runner code introduced?
