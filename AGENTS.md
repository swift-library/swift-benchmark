# AGENTS.md

- Read `README.md` first.

## Scope

This file is for maintainers/LLM contributors.
Do not duplicate end-user usage docs here.
User-facing usage docs are split by depth:

- `README.md` is the quick-start and best-practice entrypoint.
- `Documentation/UsageManual.md` is the complete user manual for API, CLI, CI,
  diagnostics, adapters, and advanced workflows.

Do not duplicate user-facing API examples outside those two files unless a
specialized architecture or decision document needs a narrowly scoped example.

## Architecture Source Of Truth

- `Documentation/Architecture/Instruments.md` is the source of truth for the
  Instruments layer.
- `Documentation/Architecture/ProductDomains.md` is the source of truth for
  product boundaries.
- `Documentation/Architecture/Benchmark.md` is the source of truth for the
  Benchmark layer and defines the Benchmark runner scope.
- `Documentation/Architecture/Report.md` is the source of truth for Report,
  baseline, attribution, diagnostics adapter, and renderer boundaries.
- `Documentation/Migrations/SignpostToInstruments.md` records the accepted
  semantic shift from Signpost-first to Instruments-first.
- `Documentation/Reference/InstrumentsAlignmentChecklist.md` is the implementation
  checklist for the Instruments alignment pass.
- `Documentation/Reference/BenchmarkCompletionChecklist.md` is the implementation
  checklist for the Benchmark completion target.
- Official Apple/Swift alignment belongs in the relevant architecture document.
  Architecture truth lives in `Documentation/Architecture/`; user-facing usage
  lives in `README.md` and `Documentation/UsageManual.md`.

## Current Completion State

The repository has completed the Instruments-first foundation and a first
Benchmark/Report implementation foundation:

1. Instruments-first alignment across runtime, macros, Signpost backend,
   fallback behavior, timeline direction, tests, and docs.
2. Benchmark core across basic declaration macros, discovery, runner plan,
   warmup, fixed iterations, samples, Dimension rows, structured results,
   tests, and docs.
3. First-pass Report, baseline/regression, host-backed CLI/plugin workflow,
   Testing/XCTest adapter helpers, Memory/allocation seams, diagnostics
   adapters, and Benchmark/Instruments timeline aggregation.

The Benchmark scope is active closure work. Current
implemented foundations include Swift-Testing-shaped traits/discovery/plan,
`Benchmark.Event.Stream`, no-`--host` package workflow for library
declarations, BenchmarkTesting bridge support for supported test-target
`@Suite(.benchmark...)` / `@Test(.benchmark...)` declarations, adaptive and
duration policies, CLI/plugin flag wiring, Memory/allocation seams, and
`xctrace` orchestration. Known boundaries remain: executable-only declarations
use the advanced `--host` override, the BenchmarkTesting bridge diagnoses
`private`/`fileprivate` tests and `@Test(arguments:)`, Testing/XCTest adapter
depth stays behind available APIs, platform memory/allocation hooks vary, and
MetricKit is future optional production diagnostics evidence.

When implementation completes, absorb durable facts into
`Documentation/Architecture/`, focused `Documentation/Reference/` checklists
where appropriate, and `README.md`.

Instruments-first semantics override stale Signpost-first implementation drift.
Treat any remaining legacy Signpost-oriented code as an implementation source
behind `SignpostRecorder`, not as public product semantics.

## Future Pre-Implementation Validation

Before future implementation starts, resolve product-boundary and toolchain
decisions in the relevant architecture or decision document. The goal is to
avoid stopping mid-implementation for choices that can be made upfront. During
execution, pause only for toolchain blockers, facts that contradict architecture
docs, or changes that would violate product boundaries.

Before code changes for the Instruments target, explicitly validate:

- Swift compiler and SwiftSyntax versions.
- Function-body macro implementation details for `@Instrumented` and `@Span`.
- Which current macro files expand directly to `OSSignposter` or `os_signpost`.
- Which existing runtime code can move directly behind `SignpostRecorder`.
- The concurrency-safe storage design for `Instruments.current`.
- The `SpanToken` shape needed for Signpost state, `EmptyRecorder`, and future
  `CompositeRecorder`.
- The baseline `swift test` result before refactoring.

Before code changes for the Benchmark target, explicitly decide:

- Product and target names.
- The public naming set from `BenchmarkCompletionChecklist.md`.
- `Benchmark` authoring shape: typealias, factory, or initializer surface.
- Runner error model.
- Clock source and test clock strategy.
- Warmup and iteration policy semantics.
- Which accepted code/algorithms are used directly and which remain seams.

## Change Rules

- Prefer additive API changes over breaking renames unless the accepted
  migration requires a breaking semantic cleanup.
- If API behavior/signatures change, update `README.md` and
  `Documentation/UsageManual.md` in the same change when the change affects
  user-facing usage.
- Keep runtime/API code in `Sources/Instruments`.
- Keep macro expansion implementation in `Sources/InstrumentsMacro`.
- Put Benchmark runner code in the Benchmark product boundary, not inside
  Instruments internals.

## Product Boundaries

- Benchmark is for repeatable measurement in test, benchmark, and CI workflows.
- Instruments is for runtime-safe instrumentation in production and test code.
- Signpost is not a product domain.
- Signpost is the Apple backend inside Instruments.
- Report is comparison, attribution, diagnostics, rendering, and export, not
  runtime recording.

## Instruments Runtime Contract

The target Instruments runtime owns:

- `Recorder`,
- `SpanToken`,
- `SpanAttributes`,
- disabled/fallback instrumentation,
- `SignpostRecorder` as the Apple backend,
- Timeline / `InMemoryRecorder` direction,
- nested span and context direction.

Apple platforms may default to `SignpostRecorder` where feasible. Non-Apple or
unsupported platforms must compile through disabled/fallback behavior.

Do not leak Signpost-specific concepts into the public Instruments model.
`OSSignposter`, `os_signpost`, signpost IDs, subsystem/category wiring, and
Apple imports belong behind `SignpostRecorder`.

## Macro Behavior Contract

Target macro surface:

- `#span`
- `#event`
- `@Instrumented`
- `@InstrumentedMembers`
- `@Span`

Macros should expand to Instruments runtime APIs such as the current
`Recorder`; they should not directly call `OSSignposter` or `os_signpost`.

`#span` should preserve return values, nested spans, throwing behavior, async
behavior where supported, and error/cancellation-safe span ending through
`defer`-style cleanup.

`#event` should record one point-in-time event and should not create a span
token or duration record.

`@Instrumented` and `@Span` require real function-body macro expansion. Do not
ship attached macros that compile but do not instrument function bodies.

Legacy APIs such as `#signpost`, `#signpost_begin`, `#signpost_end`,
`#signpot_animation`, `@Signpost`, `@Signposted`, and
`Signpost.Event.signposter` must not be retained as public compatibility
surfaces. Reuse implementation pieces internally behind `SignpostRecorder` when
useful.

## Layering

- Do not leak plugin-only helpers into runtime targets.
- Do not make macros depend on Apple Signpost APIs directly.
- Do not make Benchmark depend on Instruments internals or vice versa.
  Cross-layer attribution belongs in Report-facing adapters over public APIs.

## Licensing Guardrails

- Do not change `LICENSE`, `README` license section, or
  `COMMERCIAL_LICENSE.md` unless explicitly requested.
- Keep license wording consistent across all docs.
- For open-source release review:
  - keep public README free of workspace-internal refs metadata;
    refs tracking belongs in `.refs.yaml` / canonical refs only
  - keep `LICENSE` copyright holder/year accurate
  - for new source files, prefer SPDX + copyright header
    (for example `// SPDX-License-Identifier: AGPL-3.0-or-later`)
  - preserve third-party license/notice lines when code is copied or adapted

## Validation

For documentation-only changes, run targeted repository searches that confirm
the changed docs do not reintroduce Signpost-first public wording.

For code/API changes, run at least:

```bash
swift test
```

If macro file paths are renamed/moved, clean build artifacts first:

```bash
swift package clean
```
