# Report Architecture

## Scope / Purpose

Report is the product layer that turns Benchmark, Instruments, and optional
diagnostics data into structured, comparable, attributable, and exportable
performance evidence.

Report is not the Benchmark runner and is not the Instruments runtime. It
consumes their public outputs and preserves enough structure for local review,
CI decisions, baseline/budget comparison, agent-driven presentation, and
profiler-compatible diagnosis.

## Core Direction

Report owns the target versioned, structured performance evidence graph:

```text
Run
  -> Suite
    -> Case
      -> Iteration / Sample
        -> Span / Event
          -> DiagnosticMetric / Attachment
```

Every report detail should be traceable to typed data:

- Benchmark result facts,
- raw samples,
- `Report.Measurement` projections,
- derived `Report.Measurement.Row.metrics`,
- `Report.DimensionCurve` records,
- run/environment metadata,
- baseline comparison,
- single-run budget comparison,
- threshold verdict,
- declaration source locations,
- timeline attribution,
- diagnostics metrics,
- trace or other diagnostic attachments.

## Current Implementation Status

Current source has the structured Report foundation: `ReportDocument`,
`Report.Measurement`, row metrics, Dimension curves, baseline/budget verdicts,
diagnostics, attachments, timeline attribution, JSON output, and
console/Markdown/speedscope consumers. The Swift-Testing-style event-stream
pipeline is implemented through `Benchmark.Event.Stream`, `ReportRecorder`,
and `ReportBuilder`; CLI/plugin diagnostics, trace attachments, and `xctrace`
provenance flow into the same `ReportDocument` schema.

Output consumers should not compute independent facts or hand-build unrelated
output. They consume the same `ReportDocument`.

Swift-owned hardcoded HTML or Markdown is not the core Report deliverable. The
core deliverable is structured output that agents, templates, CI systems, and
profiler-compatible tools can consume. Optional templates may live beside the
structured schema, but presentation should not become Report semantics.

## Report Model

The Report model target includes:

- `ReportDocument`: one benchmark run report.
- schema version: the report wire contract version.
- `RunMetadata`: Swift version, package/git identity, platform, architecture,
  OS, date/time, build configuration, and optional device metadata.
- `SuiteReport`: suite-level grouping and summary.
- `CaseReport`: benchmark result, source location, measurement projection,
  metrics, baseline comparison, budget comparisons, attribution, diagnostics,
  attachments, and verdict.
- `Report.Measurement`: Codable projection of `Benchmark.Measurement`.
- `Report.Measurement.Row`: optional Dimension size, raw samples, and derived
  metrics for one measured row.
- `Report.Measurement.Metrics`: mean, median, p90, p95, p99, and other
  recomputable row metrics.
- `Report.Measurement.Metric`: selector vocabulary for baseline, budget, diff,
  and curve generation.
- `Report.DimensionCurve`: structured curve record derived from measurement
  rows and a selected metric.
- `BaselineComparison`: current value, baseline value, absolute delta,
  percentage delta, metric selector, threshold policy, and pass/fail result.
- `BudgetComparison`: current metric, limit, delta, and pass/fail result.
- `TimelineAttribution`: spans/events and timing summaries correlated to a
  sample, iteration, or case.
- `DiagnosticMetric`: measured, not configured, unavailable, or failed metric
  values.
- `DiagnosticAttachment`: trace files, diagnostic artifacts, or links scoped to
  a run/case/iteration/sample.
- `BenchmarkCommand`: a thin execution helper that runs `BenchmarkRunner` and
  emits the resulting `ReportDocument`.

The model is hardened by:

- fixture coverage for the versioned wire schema,
- baseline and budget selector coverage for
  `Report.Measurement.Metric.mean`, `.median`, `.p90`, `.p95`, and `.p99`,
- automatic per-iteration attribution capture,
- exporter-compatible attribution records,
- richer trace artifact metadata and structured attachments.

Stable IDs are part of the model, not renderer details:

- run ID,
- suite ID,
- case ID,
- iteration ID,
- sample ID,
- span/event ID and parent span ID,
- metric ID,
- attachment ID.

## Swift-Testing-Style Collection Pipeline

Report should learn Swift Testing's event, context, recorder, attachment, and
versioned machine-stream architecture. It should not copy Swift Testing's test
event schema, JUnit XML shape, ABI event-stream internals, or human output
format as Report truth.

The Report-facing collection pipeline is:

```text
BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
  -> output adapters
```

Naming should align with Swift Testing's nested-type style where the concepts
match, without nesting just for aesthetics or blurring product boundaries:

- `Benchmark.Event` mirrors Swift Testing `Event` for benchmark lifecycle
  events.
- `Benchmark.Event.Kind` mirrors `Event.Kind`.
- `Benchmark.Event.Context` mirrors `Event.Context`.
- `Benchmark.Event.Stream` is the first-class live machine-stream concept.
- `Benchmark.Event.Stream.Record` mirrors Swift Testing's record-stream idea
  without adopting its ABI namespace or schema.
- `Benchmark.Event.Stream.Configuration` carries stream output path and schema
  version settings.
- `Benchmark.Event.ConsoleOutputRecorder` is human output only and is not a
  stable contract.
- `Benchmark.Event.JSONLinesRecorder` writes a versioned JSON Lines event
  stream for live tools and adapters.
- `ReportRecorder` consumes benchmark events and builds or enriches a
  `ReportDocument`.
- `ReportDocumentEncoder` owns stable `ReportDocument` JSON encoding.
- `ReportAttachment` or `DiagnosticAttachment` models structured artifacts in
  the Report schema.

Benchmark owns the event source, lifecycle event namespace, and live event
stream. Report owns document construction, schema, comparison, diagnostics,
attachments, and output contracts. Swift Testing and XCTest adapters can project
live events or completed `ReportDocument`
verdicts and attachments into their native issue/attachment sinks, but those
sinks do not become the benchmark truth.

Report event collection should cover:

- run discovered/started/ended,
- suite/case planned/started/ended/skipped/failed,
- warmup started/ended,
- iteration/sample started/ended,
- measurement captured,
- issue or verdict cause recorded,
- diagnostic metric captured/unavailable/failed,
- attachment recorded.

`Benchmark.Event.Stream` is the collection and live-observation path. The
durable, diffable, CI-stable truth remains `ReportDocument: Codable` JSON.

## Structured Output And Renderer Boundary

The stable Report exchange contract is `ReportDocument: Codable` JSON. Console
summaries are a workflow convenience; JSON is the durable machine and agent
contract.

Core output scope:

- console summary for local use,
- JSON for machines and CI,
- profiler-compatible timeline exports such as speedscope/flamegraph records,
- structured `Report.DimensionCurve` data,
- trace artifact indexes and provenance.

All output consumers read the same report model. The CLI and SwiftPM plugin call
Report output contracts; they do not own report semantics.

Markdown, HTML, CSV, JMH, Influx, HDR, or non-core result formats are not the
primary Swift library value and are not stable core contracts. They can be
optional templates, MCP/tool conversions, or agent-driven assets over the
structured JSON/report schema rather than second fact models.

## Diagnostics Adapters

Diagnostics adapters enrich Report. They are optional and must not change the
Benchmark core result model.

Adapter roles:

- `BenchmarkObserver`: observes benchmark command lifecycle events.
- `BenchmarkExecutionObserver`: observes Benchmark iteration lifecycle through
  Benchmark public APIs when Report needs automatic attribution.
- `TimelineCorrelator`: binds Benchmark samples to Instruments spans/events.
- `MetricProvider`: gathers optional platform metrics.
- `TraceExporter`: records or links diagnostic artifacts.
- `ReportAttributor`: derives drill-down attribution from samples, spans,
  metrics, and attachments.

Adapter/provider target surface:

- `TimelineCorrelator`,
- optional Benchmark execution observation for per-iteration attribution,
- `MetricProvider`,
- `TraceExporter`,
- `BenchmarkObserver`,
- `ReportAttributor`,
- `UnavailableMetricProvider`,
- `StaticTraceExporter`,
- `TraceArtifactExporter`,
- future MetricKit snapshot providers and attachment exporters where available,
- `Memory` metric providers,
- Dimension curve derivation,
- Swift Testing and XCTest adapter helpers.

Apple-specific adapters may use Signpost timelines and Instruments trace
artifacts behind platform checks. Future production diagnostics may add
MetricKit payload evidence. Future non-Apple adapters may use their own
platform metric providers.

MetricKit is future optional Report evidence. It is primarily app-session or
run-window scoped, not deterministic per-iteration benchmark data, and it is not
current Benchmark closure acceptance.

Instruments trace support starts as public tool orchestration: run
`xcrun xctrace record`, attach the resulting `.trace`, record command metadata,
and optionally attach public `xctrace export` XML/TOC provenance. Report must
not parse private `.trace` internals as a stable API.

## Platform Fallback

Portable core:

- Benchmark results,
- samples and `Report.Measurement` projections,
- baseline comparison,
- report schema,
- JSON and summary output,
- console summaries.

Platform-enhanced diagnostics:

- Signpost timeline correlation,
- Instruments trace artifacts and exported `xctrace` metadata,
- memory/allocation providers,
- future MetricKit production diagnostics,
- future platform-specific metrics.

Unsupported diagnostics must be represented explicitly:

- `measured`,
- `notConfigured`,
- `unavailable(reason:)`,
- `failed(reason:)`.

Never report unsupported metrics as zero. Optional unavailable diagnostics stay
visible in reports. Required unavailable diagnostics fail configuration.

## Product Boundaries

- Benchmark measures workloads and produces structured results.
- Instruments records spans/events and owns runtime instrumentation.
- Report correlates, compares, attributes, and exports structured evidence.
- Diagnostics adapters provide optional scoped evidence for Report.
- CLI/plugin execution is an entry point over Benchmark and Report, not a
  separate result model.

## Closure Criteria

Report can be considered complete for the accepted scope only when:

- `ReportDocument` has versioned JSON fixture stability,
- baseline and single-run budget verdicts preserve raw causes,
- CLI/plugin check/diff/update flows use Report documents and documented exit
  codes,
- per-iteration timeline attribution links samples to span/event hierarchy and
  timing distributions,
- Dimension curves, Memory, Testing, XCTest, trace evidence, and future
  MetricKit production diagnostics enter through typed measurements,
  diagnostics, or attachments,
- unavailable optional diagnostics remain visible and required unavailable
  diagnostics fail configuration,
- no non-core exporter format is documented as the local public contract.
