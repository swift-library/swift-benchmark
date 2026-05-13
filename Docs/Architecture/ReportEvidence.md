# Report Evidence

## Scope / Purpose

This document owns the structured evidence architecture: report documents,
baseline/budget comparison, CI verdicts, output contracts, and the relationship
between live event streams and durable report snapshots.

`Report.md` remains the detailed Report layer source of truth. This document is
the capability-level view.

## Current Implementation Status

Current source implements `ReportDocument` schema version 2, run metadata,
stable suite/case/sample identities, raw samples, row metrics, baseline
comparison, single-run budgets, verdict causes, diagnostics, attachments,
timeline attribution, JSON output, and console/Markdown/speedscope
consumers. `Benchmark.Event.Stream`, `ReportRecorder`, and `ReportBuilder`
build the same durable `ReportDocument` truth from runner lifecycle events.
CLI, plugin, Testing/XCTest adapters, diagnostics, and trace attachment flows
consume that same schema.

## Evidence Flow

```text
Benchmark.Event.Stream
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
  -> baseline / budget / diff / check
  -> CLI / plugin / Testing / XCTest / agent outputs
```

## Stable Truth

The stable machine contract is `ReportDocument: Codable` JSON.

`ReportDocument` owns:

- schema version,
- run metadata,
- suite/case identities,
- source locations,
- raw samples,
- `Report.Measurement` projections,
- `Report.Measurement.Row.metrics`,
- `Report.DimensionCurve` records,
- baseline comparison,
- single-run budget comparison,
- threshold verdict,
- diagnostics metrics,
- timeline attribution,
- attachments,
- structured verdict causes.

Console output is a workflow convenience. Markdown, HTML, CSV, JMH, Influx,
HDR, and non-core result formats are not core Swift library contracts.

## Live Stream Relationship

`Benchmark.Event.Stream` is a live protocol for progress, tools, and adapters.
It is not a replacement for `ReportDocument`.

The stream can feed:

- console progress,
- Swift Testing/XCTest adapters,
- live agent/tool observation,
- `ReportRecorder`,
- `ReportBuilder`.

The final `ReportDocument` is the artifact used for baseline, diff, check, CI
verdicts, and long-lived storage.

## Baseline, Budget, Diff, Check

Report owns comparison policy:

- versioned baseline documents,
- per-suite/per-case/per-metric thresholds,
- `Report.Measurement.Metric` selectors such as mean, median, p90, p95, and
  p99,
- absolute budgets,
- relative budgets,
- single-run budgets without a saved baseline,
- structured verdict causes,
- regression exit-code input for CLI/plugin.

## Attachments

Report attachments are structured evidence, not presentation strings.

Attachment examples:

- trace artifacts,
- exported `xctrace` metadata,
- future MetricKit payload references,
- memory/allocation evidence,
- agent/tool presentation assets.

Swift Testing `Issue` and `Attachment` are adapter sinks only. They do not
become Report truth.

## Acceptance Evidence

- JSON schema fixture compatibility tests.
- Baseline read/write/update/check/diff tests.
- Budget tests without baselines.
- `Report.Measurement.Metric` selector tests for mean/median/p90/p95/p99.
- Event-to-report tests.
- Attachment provenance tests.
- CLI regression verdict and exit-code tests.
