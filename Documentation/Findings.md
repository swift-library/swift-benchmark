# Findings

This file records observed implementation findings that are not yet accepted
architecture truth. Promote a finding into `Documentation/Architecture/*`,
`Documentation/Reference/*`, or a decision document when it becomes durable
product behavior or an accepted implementation requirement.

## 2026-05-15: Nested `#span` Macro Expansion Failure

Finding: using `#span` inside another `#span` body failed to compile before the
nested Instruments macro lowering fix.

Observed in `swift-markdown-syntax` while adding temporary materialization
probes:

```swift
#span("projection.materialize.total") {
  var attributed = #span("projection.materialize.base_string") {
    AttributedString(projectedText)
  }

  #span("projection.materialize.apply_segments") {
    applySegments(to: &attributed)
  }

  return attributed
}
```

The compiler reported recursive macro expansion for the inner `#span` calls.
Before the fix, the immediate workaround was to keep probe spans as siblings
rather than nesting them inside an outer `#span` macro body:

```swift
var attributed = #span("projection.materialize.base_string") {
  AttributedString(projectedText)
}

#span("projection.materialize.apply_segments") {
  applySegments(to: &attributed)
}
```

Impact:

- Fine-grained timeline attribution can still be collected with sibling spans.
- Nested `#span` is part of the accepted Instruments macro contract.
- This was a macro expansion implementation limitation, not a benchmark measurement
  semantics issue.

Resolution:

- The freestanding `#span` macro now recursively lowers nested `#span` and
  `#event` calls inside its body before emitting the outer macro expansion.
- Focused macro expansion and runtime tests cover recursive nesting,
  return-value preservation, throwing cleanup, and async nesting.
