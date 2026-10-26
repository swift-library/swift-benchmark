# Implementation Scope

## Scope / Purpose

This document records the implemented Benchmark scope, the Apple and Swift
sources it aligns with, and the boundaries that remain open.

The implemented pipeline is:

```text
@BenchmarkSuite / @Benchmark
  -> _BenchmarkDiscovery
  -> BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event.Stream
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
  -> CLI / plugin / Swift Testing / XCTest / trace attachments
```

## Source Authority

Architecture authority is tiered.

Official Apple/Swift sources may shape architecture truth when their concepts
map cleanly to the local framework:

- Swift Testing: declaration, discovery, trait, plan, runner, event, issue,
  attachment, source-location, and recorder design.
- Apple input-size benchmark practice: size rows, amortized curves, cutoff, and
  per-size result workflow.
- XCTest: failure, issue, source context, and attachment projection.
- Instruments, OSLog, OSSignposter, and `xcrun xctrace`: public Apple
  observability and diagnostic boundaries.
- SwiftSyntax and Swift Evolution macro proposals: macro role and expansion
  constraints, and the source parsing package discovery uses.

## Implemented Capability Matrix

| Capability | Architecture authority | Implemented local state | Acceptance checks |
| --- | --- | --- | --- |
| Swift Testing declaration shape | Swift Testing | `@BenchmarkSuite` / `@Benchmark` lower to generated discovery records and sidecars without a Testing runtime dependency. | Macro expansion and integration tests |
| Discovery | Swift Testing | `_BenchmarkDiscovery` and `BenchmarkDiscovery` materialize deterministic suite/case records with source locations, traits, tags, Dimension metadata, and stable IDs. | Discovery, macro, and package fixture tests |
| Traits, tags, and scoping | Swift Testing | `BenchmarkTrait`, `BenchmarkSuiteTrait`, `BenchmarkCaseTrait`, `BenchmarkScoping`, skip traits, configuration traits, Dimension traits, and tag traits feed plan construction. | Trait merge, tag filter, skip, and planning-failure tests |
| Runner plan | Swift Testing | `BenchmarkRunner.Plan.Step` and `.Action` support measure, skip, planning failure, effective configuration, source locations, tags, and Dimension expansion. | Plan tests and runner tests |
| Runner policy | Benchmark requirements | Fixed iterations and automatic batching are the defaults; fixed batches and adaptive, minimum-duration, and maximum-duration policies are opt-in and validated before workload execution. | Runner policy, batching and invalid-configuration tests |
| Metrics | Swift runtime instrumentation hooks, platform resource APIs | Steps record wall-clock and CPU time and custom metrics in timed samples; Swift allocations, allocated bytes, retains and releases in a separate counting pass on Apple platforms; and peak memory in an isolated process; see `Metrics.md`. | Measurement, precision and isolated-host allocation tests |
| Event stream | Swift Testing | `Benchmark.Event`, `.Kind`, `.Context`, `.Stream.Record`, console recorder, and JSON Lines recorder are implemented. | Event lifecycle and JSON Lines tests |
| Report builder | Swift Testing recorder pattern, local Report | `ReportRecorder` / `ReportBuilder` consume Benchmark events and build the durable `ReportDocument`. | Event-to-report tests |
| Package command | SwiftPM plugin workflow requirement | `swift package benchmark` supports no-`--host` list/run/check/baseline write/update/diff/trace for declarations in library and test targets, measuring each step in a host process of its own; `--host` remains an advanced override. | Package fixture tests |
| Host bridge | Swift Testing discovery concept | The plugin parses declarations with SwiftSyntax, builds the package, generates an internal host with SwiftPM's toolchain, links discovered targets, binary targets and dependencies, links resource bundles beside it, and delegates to CLI semantics. | No-host and mixed-target package workflow tests |
| Filters | Swift Testing workflow shape | Suite, case, and tag filters apply during plan construction and package/CLI execution. | Filter and package tests |
| Baseline/check/diff | Local Report | Baseline write/update/check, compare/diff, per-metric thresholds, budgets, the debug-build gate, CI regression exit code, and stable JSON flow through `ReportDocument`. | Report and package workflow tests |
| Dimension | Apple input-size practice + Swift Testing traits | `.dimension(sizes:)` produces one measurement row per size; generators run outside measured iterations; Report emits Dimension curves and amortized values. | Macro Dimension, runner row, and curve tests |
| Statistics and comparison | Local Report | `Report.Statistics` per metric; comparisons per row and metric with a selectable statistic, median by default, and direction-aware regressions. | Comparison and measurement tests |
| Warnings | Local Report | Debug builds, run-condition mismatches, few samples and noisy comparisons produce warnings that never change verdicts. | Warning tests |
| Timeline attribution | Instruments + Report | Benchmark iteration spans/events correlate to samples and Report attributions. | Timeline correlation and command tests |
| Speedscope export | Local Report | Speedscope-compatible output is an optional consumer over attribution records, not a second truth model. | Renderer tests |
| Swift Testing adapter | Swift Testing | The `.benchmark` trait enrolls declarations; the adapter measures in process and projects `ReportDocument` verdicts to issues. Native hooks stay within public Testing API limits. | Adapter tests |
| XCTest adapter | XCTest | XCTest helper projects Report verdicts and JSON artifacts as adapter output while Benchmark core stays independent. | Adapter tests |
| xctrace | Instruments public tool | `XctraceRecorder` orchestrates `xcrun xctrace record`; CLI/plugin trace flows attach `.trace` artifacts and command/template provenance. | Apple diagnostics and package trace tests |
| Signpost backend | OSLog/OSSignposter | Signpost remains the Apple backend behind Instruments; Benchmark/Report consume public Instruments timeline data. | Instruments runtime/macro tests |

## Boundary Decisions

Accepted:

- Benchmark measures. Report compares, warns, attributes, and exports.
- Instruments records runtime spans/events. Signpost is only an Apple backend.
- Apple diagnostics enter as Report trace attachments.
- Swift Testing is the design skeleton for declaration, discovery, plan,
  runner, traits, events, issues, attachments, and source locations.
- `ReportDocument: Codable` JSON is the durable machine contract.
- `--host` is an advanced bridge; ordinary package workflow uses generated host
  plumbing for library declarations.

Rejected:

- Global mutable benchmark registration as architecture truth.
- External baseline/result/export formats as local public contracts.
- External directory/target naming convention as the discovery contract.
- Public provider/probe APIs for users to maintain discovery metadata.
- Swift Testing internals, ABI event streams, legacy discovery toggles, and
  runtime dependency.
- Swift Testing `Issue` or `Attachment` as Benchmark or Report truth.
- `BenchmarkTask` as the local core model.
- Automatic insertion of `#span` into benchmark bodies.
- `xctrace`, OSLogStore, or trace parsing inside Benchmark.
- Reporting unsupported platform data as zero.
- Hardcoded HTML/Markdown as core Swift library value.
- Multi-Dimension coordinates and heatmaps in the current implementation.

## Implemented Limitations / Future Boundaries

- No-host package discovery is implemented for library targets and for
  supported test-target `@Suite(.benchmark...)` / `@Test(.benchmark...)`
  declarations through the BenchmarkTesting bridge. Executable-only
  declarations still require the advanced `--host` override or moving
  declarations into a discoverable library target.
- Swift Testing native adapter depth is limited by public Testing APIs.
  Benchmark still provides trait helpers and Report-based verdict projection
  without making Benchmark core depend on Testing.
- Counting metrics require the Swift runtime's instrumentation hooks and are
  recorded on Apple platforms only. Peak memory is attributable only
  in a process that measures one step.
- The package workflow supports Apple platforms; Linux runs the libraries.
- Multi-Dimension coordinates, heatmaps, and presentation templates remain
  future proposals over the stable `ReportDocument`.

## Acceptance Checks

Current acceptance is proven by:

- full `swift test` passing with 162 tests in 29 suites on 2026-10-26, on
  macOS with Xcode 27.0, plus generic iOS builds of the library schemes;
- macro expansion tests for benchmark declarations, traits, source locations,
  and Dimension lowering;
- plan tests for trait merge, skips, planning failures, filters, tags, and
  Dimension expansion;
- runner tests for fixed, adaptive, minimum-duration, maximum-duration,
  batching, metrics, and error phases;
- precision tests for wall-clock accuracy, sub-microsecond batching, and exact
  allocation counts in an isolated host;
- event stream JSON Lines and event-to-report tests;
- fixture package tests for `swift package benchmark`
  list/run/check/baseline write/update/diff/trace without user-written host
  boilerplate, including packages with resources, binary targets, and C,
  Objective-C and C++ targets;
- Report fixture tests for samples, statistics, Dimension curves, baselines,
  budgets, verdict causes, warnings, attachments, and scopes;
- Swift Testing and XCTest adapter tests over `ReportDocument` verdicts;
- Apple diagnostics tests for `xctrace record`, unavailable paths, trace
  attachment provenance, and package trace workflow.
