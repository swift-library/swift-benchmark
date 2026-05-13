# Implementation Scope

## Scope / Purpose

This document records the implemented Benchmark scope. It is
not an upstream comparison matrix. Durable architecture truth names local concepts
and official Apple/Swift alignment only; temporary comparison evidence remains
outside durable architecture docs.

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
  -> CLI / plugin / Swift Testing / XCTest / diagnostics
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
  constraints.

MetricKit is official Apple API surface, but it is future optional production
diagnostics evidence for this package because it is app/session scoped. It is
not current Benchmark acceptance.

## Implemented Capability Matrix

| Capability | Architecture authority | Implemented local state | Acceptance evidence |
| --- | --- | --- | --- |
| Swift Testing declaration shape | Swift Testing | `@BenchmarkSuite` / `@Benchmark` lower to generated discovery records and sidecars without a Testing runtime dependency. | Macro expansion and integration tests |
| Discovery | Swift Testing | `_BenchmarkDiscovery` and `BenchmarkDiscovery` materialize deterministic suite/case records with source locations, traits, tags, Dimension metadata, and stable IDs. | Discovery, macro, and package fixture tests |
| Traits, tags, and scoping | Swift Testing | `BenchmarkTrait`, `BenchmarkSuiteTrait`, `BenchmarkCaseTrait`, `BenchmarkScoping`, skip traits, configuration traits, Dimension traits, and tag traits feed plan construction. | Trait merge, tag filter, skip, and planning-failure tests |
| Runner plan | Swift Testing | `BenchmarkRunner.Plan.Step` and `.Action` support measure, skip, planning failure, effective configuration, source locations, tags, and Dimension expansion. | Plan tests and runner tests |
| Runner policy | Benchmark requirements | Fixed iterations remain default; adaptive, minimum-duration, and maximum-duration policies are opt-in and validated before workload execution. | Runner policy and invalid-configuration tests |
| Event stream | Swift Testing | `Benchmark.Event`, `.Kind`, `.Context`, `.Stream.Record`, console recorder, and JSON Lines recorder are implemented. | Event lifecycle and JSON Lines tests |
| Report builder | Swift Testing recorder pattern, local Report | `ReportRecorder` / `ReportBuilder` consume Benchmark events and build the durable `ReportDocument`. | Event-to-report tests |
| Package command | SwiftPM plugin workflow requirement | `swift package benchmark` supports no-`--host` list/run/check/baseline write/update/diff/trace for declarations in library targets; `--host` remains an advanced override. | Package fixture tests |
| Host bridge | Swift Testing discovery concept | The plugin scans declarations, builds the package, generates an internal host, links discovered targets and dependencies, and delegates to CLI semantics. | No-host package workflow test |
| Filters | Swift Testing workflow shape | Suite, case, and tag filters apply during plan construction and package/CLI execution. | Filter and package tests |
| Baseline/check/diff | Local Report | Baseline write/update/check, compare/diff, thresholds, budgets, CI regression exit code, and stable JSON flow through `ReportDocument`. | Report and package workflow tests |
| Dimension | Apple input-size practice + Swift Testing traits | `.dimension(sizes:)` produces one measurement row per size; generators run outside measured iterations; Report emits Dimension curves and amortized values. | Macro Dimension, runner row, and curve tests |
| Metric selectors | Local Report | `Report.Measurement.Metric` selectors cover mean, median, p90, p95, and p99 for baseline, budget, diff, and curve workflows. | Selector and schema tests |
| Timeline attribution | Instruments + Report | Benchmark iteration spans/events correlate to samples and Report attributions. | Timeline correlation and command tests |
| Speedscope export | Local Report | Speedscope-compatible output is an optional consumer over attribution records, not a second truth model. | Renderer tests |
| Swift Testing adapter | Swift Testing | Benchmark trait helpers and adapter report/issue projection consume `BenchmarkCommand` / `ReportDocument`. Native hooks stay within public Testing API limits. | Adapter tests |
| XCTest adapter | XCTest | XCTest helper projects Report verdicts and JSON artifacts as adapter output while Benchmark core stays independent. | Adapter tests |
| Resident memory | Platform memory APIs | Resident memory provider reports measured/unavailable states without fake zero values. | Memory tests |
| Allocation/resource regression | Swift performance discipline | Allocation snapshots, leak tolerance, preheat/repeated-run aggregation, remaining allocation checks, and FD/resource leak checks are modeled in Memory. | Memory regression and resource tests |
| MetricKit | MetricKit | Future optional production diagnostics evidence; no current acceptance requirement and no Benchmark core dependency. | Future boundary documented |
| xctrace | Instruments public tool | `XctraceRecorder` orchestrates `xcrun xctrace record`; CLI/plugin trace flows attach `.trace` artifacts and command/template provenance. | Apple diagnostics and package trace tests |
| Signpost backend | OSLog/OSSignposter | Signpost remains the Apple backend behind Instruments; Benchmark/Report consume public Instruments timeline data. | Instruments runtime/macro tests |

## Boundary Decisions

Accepted:

- Benchmark measures. Report compares, attributes, diagnoses, and exports.
- Instruments records runtime spans/events. Signpost is only an Apple backend.
- Apple diagnostics enter through Report diagnostics and attachments.
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
- MetricKit, `xctrace`, OSLogStore, or private trace parsing inside Benchmark.
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
- Platform memory and allocation hooks vary by OS/toolchain. Unsupported data
  must remain explicit `unavailable`, `notConfigured`, or `failed` states.
- MetricKit remains future optional production diagnostics evidence.
- Multi-Dimension coordinates, heatmaps, and presentation templates remain
  future proposals over the stable `ReportDocument`.

## Acceptance Evidence

Current acceptance is proven by:

- full `swift test` passing with 75 tests in 15 suites on 2026-05-13;
- macro expansion tests for benchmark declarations, traits, source locations,
  and Dimension lowering;
- plan tests for trait merge, skips, planning failures, filters, tags, and
  Dimension expansion;
- runner tests for fixed, adaptive, minimum-duration, maximum-duration, and
  error phases;
- event stream JSON Lines and event-to-report tests;
- fixture package tests for `swift package benchmark`
  list/run/check/baseline write/update/diff/trace without user-written host
  boilerplate;
- Report schema fixture tests for samples, row metrics, Dimension curves,
  baselines, budgets, verdict causes, diagnostics, attachments, and scopes;
- Swift Testing and XCTest adapter tests over `ReportDocument` verdicts;
- Memory/allocation tests for unavailable/notConfigured/failed/measured states,
  resident memory, allocation/deallocation/net/peak values, leak tolerance, and
  resource leaks;
- Apple diagnostics tests for `xctrace record`, unavailable paths, trace
  attachment provenance, and package trace workflow.
