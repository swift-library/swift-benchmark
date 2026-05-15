# Findings

This file records observed implementation findings that are not yet accepted
architecture truth. Promote a finding into `Documentation/Architecture/*`,
`Documentation/Reference/*`, or a decision document when it becomes durable
product behavior or an accepted implementation requirement.

## 2026-05-15: Nested `#span` Macro Expansion Fails

Finding: using `#span` inside another `#span` body currently fails to compile.

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

The compiler reports recursive macro expansion for the inner `#span` calls.
The immediate workaround is to keep probe spans as siblings rather than nesting
them inside an outer `#span` macro body:

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
- A parent aggregate span currently has to be provided by surrounding stable
  instrumentation, not by nesting `#span` around inner `#span` probes.
- This is a macro expansion/tooling limitation, not a benchmark measurement
  semantics issue.

Follow-up:

- Decide whether nested `#span` should be supported as part of the Instruments
  macro contract.
- If supported, add a focused macro expansion test that covers nested
  expression/body spans, return-value preservation, and throwing behavior.
- If not supported, document sibling spans as the supported pattern in
  `Documentation/UsageManual.md` and the Instruments architecture docs.
