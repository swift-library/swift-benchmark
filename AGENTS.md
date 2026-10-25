# swift-benchmark Agent Guide

- Read `README.md` first.

## First-Principles Work

- Name the behavior, root cause, invariant, owner, data flow, and validation
  before changing reusable files.
- Change the owning layer: runtime/API code, macro implementation, report
  layer, current architecture truth, reference checklist, or docs.
- Keep changes traceable to the request, a cited source, or the owning invariant.
- Validate code/API changes with `swift test` unless the task explicitly
  narrows validation.

## Task Route

- Before changing versions, dependencies, packaging or release workflows, read
  `VERSIONING.md`, or the organization VERSIONING the project adopts, for
  version rules and `Documentation/Reference/Release.md` for this repository's
  release facts and check entry points.

## Scope

This file is for maintainers/LLM contributors.
Do not duplicate end-user usage docs here.
User-facing usage docs are split by depth:

- `README.md` is the quick-start and best-practice entrypoint.
- `Documentation/UsageManual.md` is the complete user manual for API, CLI, CI,
  metrics, adapters, and advanced workflows.

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
  baseline, warning, attribution, trace attachment, and renderer boundaries.
- `Documentation/Architecture/Metrics.md` is the source of truth for what a
  benchmark sample measures and how.
- `Documentation/Migrations/SignpostToInstruments.md` records the accepted
  semantic shift from Signpost-first to Instruments-first.
- `Documentation/Reference/InstrumentsAlignmentChecklist.md` is the implementation
  checklist for the Instruments alignment pass.
- `Documentation/Reference/BenchmarkCompletionChecklist.md` is the implementation
  checklist for the Benchmark completion target.
- Official Apple/Swift alignment belongs in the relevant architecture document.
  Architecture truth lives in `Documentation/Architecture/`; user-facing usage
  lives in `README.md` and `Documentation/UsageManual.md`.

## Canonical Artifacts

- Treat conversation, review feedback, plans, and intermediate attempts as
  editing input. Recompute the complete accepted result before finalizing.
- Active artifacts depend only on that result and their repository role, not
  on the editing path. Apply this to code, symbols, files, wrappers, branches,
  configuration, schemas, defaults, generated sources, scripts, templates,
  automation, comments, DocC, diagrams, tests, fixtures, snapshots, examples,
  and normative docs.
- If an intermediate result is `A + B` and the accepted result is `A`, express
  `A` directly. Remove `B` and its residual surface rather than retaining names
  such as `AOnly` or `AWithoutB`, or prose such as "B was removed."
- Normalize by semantic identity and artifact role, not by token. A rejected
  current capability does not invalidate a distinct historical fact,
  migration, ownership record, or safety boundary that uses the same term.
- Keep a negative constraint only when excluding `B` is independently required
  by a current compatibility, safety, or ownership invariant.
- A disabled B flag, skipped B test, dead B branch, retained B fixture, or
  "do not add B" rule is residue when it exists only because B was attempted;
  disabled state alone is not an invariant.
- Keep change history only in commits, pull requests, changelogs, release
  records, migrations, archives, or accepted decision records with durable
  value. Do not create a history artifact merely to preserve a correction.
- Preserve role-owned facts unless separate evidence changes them; do not
  rewrite history or ownership merely to make a rejected term disappear.
- Leave an already-correct history, migration, provenance, ownership, or safety
  artifact unchanged when the task does not change its facts. Do not polish or
  restate it merely because it is relevant to the current edit.
- Comments explain non-obvious current semantics and invariants, not the
  sequence of edits.
- Before handoff, verify that a new agent with no editing conversation can
  derive the complete current behavior, boundaries, and operating guidance
  without mentally subtracting a rejected concept.

## Authority

- `AGENTS.md` is the agent guide for maintainer and agent work.
- `README.md` and `Documentation/UsageManual.md` own user-facing usage.
- `Documentation/Architecture/*` owns current architecture truth.
- `Documentation/Reference/*` owns implementation checklists and supporting
  reference material.
- `Package.swift` owns SwiftPM package structure.

## Boundary Guardrails

- Do not promote machine-local paths, one-run state, fixture-only values, or
  temporary execution state into reusable docs, scripts, templates, or
  automation.
- If a value changes by input, toolchain, benchmark host, or environment, pass
  it in, configure it, derive it, or link to the owning artifact.
- Do not duplicate end-user usage examples outside the user-facing docs unless
  a specialized architecture or decision document needs a narrowly scoped
  example.

## Current Completion State

The repository has completed the Instruments-first foundation and a first
Benchmark/Report implementation foundation:

1. Instruments-first alignment across runtime, macros, Signpost backend,
   fallback behavior, timeline direction, tests, and docs.
2. Benchmark core across basic declaration macros, discovery, runner plan,
   warmup, fixed iterations, samples, Dimension rows, structured results,
   tests, and docs.
3. First-pass Report, baseline/regression, host-backed CLI/plugin workflow,
   Testing/XCTest adapter helpers, and Benchmark/Instruments timeline
   aggregation.
4. Credible measurement: built-in and custom metrics, automatic batching,
   per-step host processes, per-row and per-metric comparisons with warnings,
   SwiftSyntax-only discovery, and the `Macros` trait.

The implemented Benchmark/Report scope is defined by the architecture
documents. Current capabilities include Swift-Testing-shaped traits/discovery/plan,
`Benchmark.Event.Stream`, no-`--host` package workflow for library and test
declarations with one host process per step, BenchmarkTesting bridge support for
supported test-target `@Suite(.benchmark...)` / `@Test(.benchmark...)`
declarations, wall-clock, CPU, allocation, reference-counting, peak-memory and
custom metrics, batching, adaptive and duration policies, and `xctrace`
recording. Known boundaries remain: executable-only declarations use the
advanced `--host` override; the BenchmarkTesting bridge diagnoses
`private`/`fileprivate` tests and extensions of types from other targets;
argument rows are supported. Testing/XCTest adapter depth stays behind available
APIs, counting metrics need the Swift runtime's instrumentation hooks, and the
package workflow supports Apple platforms.

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
- Report is comparison, warnings, attribution, trace attachments, rendering,
  and export, not runtime recording.

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

- Do not change `LICENSE.txt`, `NOTICE`, or the `README` license section unless
  explicitly requested.
- Keep license wording consistent across all docs.
- For open-source release review:
  - keep public README free of workspace-internal refs metadata;
    refs tracking belongs in `.refs.yaml` / canonical refs only
  - keep `LICENSE.txt` copyright holder/year accurate
  - for new source files, prefer SPDX + copyright header
    (for example `// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception`)
  - preserve third-party license/notice lines when code is copied or adapted

## Operating Notes

Keep validation tied to the changed behavior and owning layer.

## Validation

The package requires Swift 6.3 and deployment minimums of iOS 18 and macOS 15
for all products. Shared CI tests with Xcode 26.6 on macOS 26 (bundled Swift
6.3, the minimum) and with Xcode 27.2 and 27.1, tests on a Swift 6.3 Linux
image, and builds the libraries for iOS; the latest SDKs check availability
against the deployment floors. `Documentation/Reference/Release.md` records the
matrix.

Shared CI reads `.github/swift-package.json` for compiler, formatting, DocC and
repository-command validation. Required checks are `policy / policy` and
`validate / result`. Release identity and compatibility declarations live in
`.github/release.json`.

For documentation-only changes, run targeted repository searches that confirm
the changed docs do not reintroduce Signpost-first public wording.

For code/API or CI changes, run local validation and every `commands` entry in
`.github/swift-package.json`:

```bash
swift build
swift test
swift build -c release
xcrun swift-format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests Plugins
```

If macro file paths are renamed/moved, clean build artifacts first:

```bash
swift package clean
```

## Code Review Rules

### Compatibility and versioning

- Flag a change to the compatibility surface recorded in
  `Documentation/Reference/Release.md`, such as public API, observable
  behavior or a raised minimum platform or Swift version, without the
  changelog entry VERSIONING requires. Record unreleased compatibility changes
  under `## Unreleased` with a **Breaking** marker and the new minimums when
  requirements change. Assign the version at release time under VERSIONING.

### Claims

- Flag README, DocC, or release-note statements that the code and tests do
  not support: capabilities that do not exist, existing behavior described as
  new, or platforms CI does not build. Safe path: describe what the code
  shows.

### Public documentation

- Flag a new public symbol without a documentation comment, and public prose
  that compares the package with other projects or describes internal
  process. Safe path: document the symbol, and describe only this package's
  own behavior.

### Tests

- Flag a behavior change without a test that would fail before the change.
  Safe path: add the test beside the existing suite for that behavior.
