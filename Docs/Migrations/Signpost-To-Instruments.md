# Signpost To Instruments Migration

## Scope / Purpose

This migration record captures the accepted semantic shift from the
Signpost-first package implementation to the target Instruments-first product
model.

It is not an implementation guide and does not define target layout changes.

## Old Model

The previous source implementation looked like a Signpost macro wrapper, and
earlier repository-facing docs did too:

- root `README.md` was previously titled `SignpostMacros`,
- public examples previously used `Signpost`, `Signpost.Event`, and
  `#signpost`,
- public macros included `#signpost`, `#signpost_begin`, `#signpost_end`, and
  `#signpot_animation`,
- `Package.swift` exposed a compatibility `SignpostMacros` product,
- macro expansion called Signpost-oriented runtime helpers or
  `OSSignposter` APIs directly.

This old implementation is an implementation source. It should not remain the
public semantic model.

## New Model

The accepted public model is Instruments-first:

- `Instruments` is the product domain for runtime-safe instrumentation.
- `InstrumentsMacros` provides macro ergonomics.
- Signpost is the Apple backend inside Instruments.
- Macros emit Instruments semantics, not Signpost semantics.

Desired public macro semantics:

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

@InstrumentedMembers
struct Store {
  func load() throws -> Item {
    ...
  }
}
```

## Breaking Direction

The following names should not remain primary public product semantics:

- `#signpost`,
- `@Signpost`,
- `@Signposted`,
- `Signpost` as a top-level domain concept,
- Signpost-first README and examples.

Compatibility is not retained as a target product policy. Legacy Signpost names
are migration sources and should be removed from the target public surface.

## Boundary Rules

- Do not treat Signpost wrappers as the semantic source of truth.
- Do not make macros call `OSSignposter` or `os_signpost` directly in the target
  model.
- Keep Apple-specific behavior in `SignpostRecorder`.
- Keep non-Apple behavior compiling through disabled/fallback instrumentation.
- Do not introduce Benchmark runner or Report aggregation inside the
  Instruments migration layer. Benchmark completion is a separate repository
  target with architecture truth in `Docs/Architecture/Benchmark.md`.

## Current Status

The migration is implemented for the public Signpost-first surface:

- `SignpostMacros` was removed from `Package.swift`.
- Public macros `#signpost`, `#signpost_begin`, `#signpost_end`, and
  `#signpot_animation` were removed.
- Public `Signpost`, `Signpost.Event`, subsystem/category helpers, and
  `_signpostInner` were removed.
- Macro expansion now targets `Instruments.current` runtime APIs.
- Apple Signpost behavior is isolated in `SignpostRecorder`.
- `EmptyRecorder`, `InMemoryRecorder`, and `Timeline` provide fallback and
  inspection behavior.

Function-level `@Span` and `@Instrumented` are implemented as real body macros.
Type/extension bulk instrumentation is implemented as `@InstrumentedMembers`.
The originally desired same-name type-level `@Instrumented` spelling remains
blocked by the current Swift macro attachment-role model; see
`Docs/Architecture/Instruments.md` for the compiler evidence behind the spelling
split.

## Related Documents

- `../Architecture/ProductDomains.md`
- `../Architecture/Instruments.md`
- `../Reference/InstrumentsAlignmentChecklist.md`
