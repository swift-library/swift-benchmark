# Report Architecture

## Scope / Purpose

Report is the product layer that turns Benchmark event records and
Instruments timelines into structured, comparable, attributable, and
exportable performance reports.

Report is not the Benchmark runner and is not the Instruments runtime. It
consumes their public outputs and preserves enough structure for local review,
CI decisions, baseline/budget comparison, agent-driven presentation, and
profiler-compatible diagnosis.

## Report Graph

```text
Run
  -> Suite
    -> Case
      -> Row (argument row or Dimension size)
        -> Sample (per-call value of each metric)
          -> Span / Event attribution
      -> Attachment
```

Every report detail is traceable to typed data:

- raw samples with their batch sizes and per-call metric values,
- `Report.Measurement` rows with per-metric `Report.Statistics`,
- `Report.DimensionCurve` records,
- run metadata,
- baseline and budget comparisons per row and metric,
- verdict causes,
- warnings,
- declaration source locations,
- timeline attribution,
- trace attachments.

## Report Model

The public model:

- `ReportDocument`: one run's report, with run metadata, suites, run warnings
  and a summary. Its JSON encoding is the wire contract; it carries no schema
  version, and a document from another release that fails to decode is
  regenerated rather than migrated.
- `RunMetadata`: Swift version, package and git identity, platform,
  architecture, OS version, device model, generation date and build
  configuration. `RunMetadata.local(id:)` describes the current process.
- `SuiteReport` and `ReportSummary`: grouping, counts of regressions, budget
  failures and warnings, and the run verdict.
- `CaseReport`: source location, configuration, tags, measurement, baseline
  and budget comparisons, Dimension curves, attribution, attachments, verdict,
  verdict causes and case warnings.
- `Report.Measurement` and `Report.Measurement.Row`: the Codable projection of
  `Benchmark.Measurement`; each row has its size or argument row identity, raw
  `SampleReport`s, the metrics it measured, recomputed statistics and, when
  recorded, its `Benchmark.AllocationSites`.
- `Report.Statistics` and `Report.Statistic`: count, min, max, mean, median,
  standard deviation, p90, p95, p99 and mild and severe outlier counts of one
  metric, and the selector for one of them.
- `Report.DimensionCurve` and `Report.Complexity`: one statistic of one metric
  across a case's sizes, with amortized per-unit values and the growth model
  that best fits them.
- `Report.ConfidenceInterval`: the range that holds a comparison's difference
  with a stated confidence.
- `ComparisonPolicy`, `ThresholdPolicy` and `BudgetPolicy`: the statistic,
  default and per-metric thresholds, and budgets a comparison applies.
- `BaselineDocument` and `BaselineCase`: the measurements of an earlier run.
- `BaselineComparison` and `BudgetComparison`: the result of comparing one
  metric of one row; a baseline comparison carries its confidence interval
  and significance.
- `ReportVerdict` and `ReportVerdictCause`: typed verdicts and their causes,
  naming the metric, statistic, row, actual and expected values.
- `ReportWarning`: conditions that make comparisons less trustworthy.
- `TimelineAttribution`, `SpanAttribution`, `EventAttribution` and
  `SpanTimingSummary`: spans and events correlated to a sample.
- `DiagnosticAttachment`: trace files and other artifacts scoped to a run or
  case.

Stable IDs are part of the model, not renderer details: run, suite, case,
iteration and sample IDs, span/event IDs with parent span IDs, curve IDs and
attachment IDs, all derived from names, sizes, argument rows and iterations.

## Collection Pipeline

```text
BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event.Stream.Record
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
```

Benchmark owns the event source, the lifecycle event namespace and the live
event stream; Report owns document construction, comparison, attribution,
attachments and output. The names follow Swift Testing's nested-type style where
the concepts match: `Benchmark.Event`, `Benchmark.Event.Kind`,
`Benchmark.Event.Context`, `Benchmark.Event.Stream` and
`Benchmark.Event.Stream.Record`, with `InMemoryRecorder`, `ConsoleRecorder` and
`JSONLinesRecorder` as recorders. Report does not copy Swift Testing's event
schema, ABI stream or output format.

`ReportBuilder` builds the same document from records that
`ReportDocument(metadata:results:)` builds from runner results. That equivalence
lets the package workflow measure each step in a separate host process: each
host returns its records and run metadata, the CLI concatenates the records in
the order the steps ran, and one builder produces the document.

## Comparison

Comparisons are made per row: each argument row or Dimension size of a case is
compared with the row of the baseline case that has the same identity. Every
metric both rows measured is compared using the policy's statistic, median by
default. A metric regresses when it moves past its threshold, 10% by default,
in its worse direction, which the measured metric's direction decides, and the
change is significant. Thresholds are relative percentages or absolute amounts
in the metric's unit and can differ per metric.

Significance comes from a bootstrap confidence interval of the difference
between the two rows' statistics at 95%: 1,000 resamples of each side's values
with replacement, seeded from the suite, case, row, metric and statistic so the
same values always give the same interval. A change whose interval includes
zero can be noise and passes. A side with fewer than two values, as a counting
metric has, gets no interval, and the threshold alone judges it; values that
never vary give an interval of the difference itself, so deterministic metrics
are judged by the threshold too.

A case with three or more Dimension sizes gets a complexity fit on each curve:
every model from O(1) to O(n³) is fitted by least squares as
`value ≈ coefficient × f(size)`, and the model with the smallest root-mean-square
error relative to the mean value wins.

Budgets limit one statistic of one metric, for every case or for one case. The
limit is in the measured metric's unit; it is an upper bound for metrics where
lower is better and a lower bound for metrics where higher is better. A budget
on a metric the row did not measure is not compared.

Warnings never change a verdict. The run warns when it measured a debug build
and when its baseline was recorded under different platform, OS version,
architecture, device model, Swift version or build configuration. A compared
row warns when it has fewer than five timed samples, when a compared
metric's spread, in the row or its baseline row, reaches the threshold (the
coefficient of variation for a relative threshold, the standard deviation for
an absolute one), and when at least a tenth of a compared metric's values, out
of five or more, are severe outliers. Outliers follow Tukey's fences, 1.5 and 3
interquartile ranges outside the quartiles, with the range counted as at least
1% of the median so values a clock step apart are not outliers.

## Output And Renderer Boundary

`ReportDocument: Codable` JSON is the stable exchange contract for machines,
agents and CI. Report also renders the console summary, a Markdown summary for
pull request comments and speedscope exports for the CLI, with timelines as
evented profiles and allocation sites as sampled profiles weighted by
allocations and by bytes per call; those
renderers are package-internal, read the same document and add no facts of
their own, and their layout is not a contract. HTML, CSV and other
presentations belong in templates or tools over the JSON, not in Report.

## Host Boundary

`BenchmarkHost.run(discoveries:arguments:metadata:)` is the public entry point
of an executable the CLI measures in: the host generated by the command plugin,
or an executable passed with `--host`. The CLI drives it through a
package-internal protocol: `list` returns the plan with the host's run metadata,
and `measure` measures selected steps and returns their records and timeline
attributions, written to a file the CLI names. Comparison, gating, trace
attachments and rendering stay in the CLI, which builds the report with the
package-internal `BenchmarkCommand`. The testing adapters use the same command
to measure in process.

## Attribution And Traces

`BenchmarkTimelineObserver` observes measured calls through Benchmark's public
execution observer API and records Instruments spans and events into a
timeline. `TimelineCorrelator` binds each sample to the spans and events of its
iteration, including descendants of the iteration's root span.

Trace attachments come from the CLI: `--trace` and `--required-trace` attach an
existing trace to every case, and `--xctrace-output` records one with
`xcrun xctrace record` and attaches it with its command metadata. Report does
not parse `.trace` internals.

## Platform Fallback

The report model, comparisons, JSON and console output are portable. Signpost
timelines and xctrace recording are Apple platform enhancements; elsewhere the
xctrace runner reports the command as unavailable. Which metrics a sample has
is Benchmark's concern: metrics a platform cannot measure are absent from the
samples, never reported as zero, and comparisons skip them.

## Product Boundaries

- Benchmark measures workloads and produces structured results and records.
- Instruments records spans/events and owns runtime instrumentation.
- Report correlates, compares, attributes, and exports structured report data.
- CLI/plugin execution is an entry point over Benchmark and Report, not a
  separate result model.

## Acceptance

Report satisfies its scope when:

- the JSON fixture round-trips and exposes typed verdict causes
  (`ReportDocumentTests`);
- event-built documents equal runner-built documents, including rows that
  measured different metrics (`ReportDocumentTests`, `ReportComparisonTests`);
- documents built from per-step host measurements match one-process runs
  (`BenchmarkHostTests`);
- comparisons are per row, per metric and direction-aware, and budgets follow
  the measured metric's direction (`ReportComparisonTests`);
- a change that noise can explain passes, a significant one past its threshold
  fails, single values are judged by the threshold, intervals repeat for the
  same values, outliers follow Tukey's fences, complexity fits find each
  growth model, and the Markdown summary lists comparisons
  (`ReportStatisticsTests`);
- warnings cover debug builds, run-condition mismatches, few samples, noise
  and outliers (`ReportWarningTests`, `ReportStatisticsTests`);
- timeline attribution links samples to span/event hierarchies
  (`TimelineCorrelationTests`, `BenchmarkCommandTests`);
- CLI check, diff and baseline flows use Report documents and documented exit
  codes (package workflow tests).
