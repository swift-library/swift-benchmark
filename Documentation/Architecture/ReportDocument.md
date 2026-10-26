# Report Document

## Scope / Purpose

This document owns the capability-level view of structured reports: report
documents, baseline/budget comparison, CI verdicts, output contracts, and the
relationship between live event streams and durable report snapshots.

`Report.md` remains the detailed Report layer source of truth.

## Data Flow

```text
Benchmark.Event.Stream records (one host process per step)
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
  -> baseline / budget / diff / check, warnings
  -> CLI / plugin / Testing / XCTest / agent outputs
```

## Stable Truth

The stable machine contract is `ReportDocument: Codable` JSON. It carries no
schema version: a document or baseline from a release with another shape fails
to decode and is regenerated.

`ReportDocument` owns:

- run metadata,
- suite/case identities and source locations,
- raw samples with batch sizes and per-call values of each metric,
- `Report.Measurement` rows with per-metric statistics,
- `Report.DimensionCurve` records,
- baseline and budget comparisons per row and metric,
- structured verdict causes,
- run and case warnings,
- timeline attribution,
- trace attachments.

Console output is a workflow convenience. HTML, CSV, Markdown and other result
formats are not Swift library contracts.

## Live Stream Relationship

`Benchmark.Event.Stream` is the live protocol for progress, tools and adapters,
and the input `ReportBuilder` builds documents from. It is not a replacement for
`ReportDocument`. The final document is the artifact used for baselines, diff,
check, CI verdicts and long-lived storage.

## Baseline, Budget, Diff, Check

Report owns comparison policy:

- baseline documents written from reports,
- the statistic comparisons use, median by default,
- a default threshold and per-metric thresholds, relative or absolute,
- budgets on one statistic of one metric, for every case or one case,
- per-row comparison of argument rows and Dimension sizes,
- direction-aware regressions,
- structured verdict causes,
- regression exit-code input for the CLI and plugin.

The CLI applies the policy to measurements from host processes and to saved
reports alike, and refuses to check a debug build without `--allow-debug`.

## Attachments

Report attachments are structured data, not presentation strings: trace
artifacts with their recording command and tool metadata. Swift Testing
`Issue` and `Attachment` are adapter sinks only; they do not become Report
truth.

## Acceptance Checks

- JSON fixture round-trip and typed verdict causes (`ReportDocumentTests`).
- Baseline read errors, write/update/check/diff flows (`ReportWarningTests`,
  package workflow tests).
- Budgets without baselines and per-metric thresholds
  (`ReportComparisonTests`, `ComparisonArgumentsTests`).
- Event-to-report equivalence (`ReportDocumentTests`, `BenchmarkHostTests`).
- Trace attachment provenance (`AppleDiagnosticsTests`, `BenchmarkHostTests`).
- CLI regression verdicts and exit codes (package workflow tests).
