# Capability Map

## Scope / Purpose

This document routes readers to the accepted architecture by capability group.
It is intentionally short. Capability details live in the category documents
listed below, not in this index.

Use this map to answer:

- which capability owns a user workflow,
- which product domains participate,
- which architecture documents define the truth,
- which implementation phases and acceptance checks close the capability.

## Category Documents

- `SwiftTestingAlignment.md`: Swift Testing alignment strategy, accepted naming
  mappings, and rejected coupling.
- `Instruments.md`: runtime instrumentation, macros, recorders, timelines, and
  Signpost backend boundary.
- `BenchmarkDeclarations.md`: macro-first authoring, suite/case traits,
  Dimension traits, and discovery.
- `BenchmarkExecution.md`: `BenchmarkRunner.Plan`, runner policy, samples,
  Measurement rows, and `Benchmark.Event.Stream`.
- `ReportDocument.md`: `ReportDocument`, live stream relationship, baseline,
  budget, diff, check, and output contracts.
- `Dimension.md`: Dimension-first measurement and Apple-aligned input-size
  semantics.
- `Metrics.md`: built-in and custom metrics, timing and counting, peak memory,
  batching, and platform availability.
- `AppleDiagnostics.md`: `xcrun xctrace` recording and trace attachments.
- `WorkflowAdapters.md`: SwiftPM command, CLI/plugin, Swift Testing adapter,
  and XCTest adapter workflows.
- `ProductDomains.md`: product ownership boundaries across all categories.
- `ImplementationScope.md`: implemented-vs-target gap matrix,
  Apple/Swift alignment policy, closure order, and acceptance checks.

## Capability Flow

The target system should read as one connected capability graph:

```text
@BenchmarkSuite / @Benchmark
  -> _BenchmarkDiscovery
  -> BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event.Stream
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
  -> baseline / budget / diff / check / warnings
  -> Dimension curves / timeline attribution / trace attachments
  -> CLI / plugin / Swift Testing / XCTest / agent outputs
```

Swift Testing alignment is the default for declaration, traits, discovery,
plan, runner, event, context, recorder, source-location, issue, and attachment
design. Benchmark-specific capabilities extend that skeleton for measurement,
metrics, batching, raw samples, Dimension rows and curves, attribution,
baselines, budgets, warnings, and diff workflows.

Current source implements the nodes in the graph for the accepted scope:
declaration macros, traits/tags, discovery, runner plans, event streams,
Report construction, package command workflow with per-step host processes,
adapters, metrics, and trace attachments. `ImplementationScope.md` owns the
implemented capability matrix and future-boundary notes.

## Classification Rules

- Product-domain ownership remains in `ProductDomains.md`.
- Swift Testing alignment rules live in `SwiftTestingAlignment.md`.
- Benchmark declaration and trait rules live in `BenchmarkDeclarations.md`.
- Benchmark plan, runner, measurement, and event-stream rules live in
  `BenchmarkExecution.md`.
- Runtime instrumentation, recorder backends, and macro instrumentation rules
  live in `Instruments.md`.
- Report schema, baseline, budget, diff, output contract, and durable report
  rules live in `ReportDocument.md` and `Report.md`.
- Dimension, metrics, and Apple-only diagnostics live in their own topic
  documents.
- Official source alignment and local decisions live in architecture docs.
- Durable implementation facts move back into README and architecture docs.

Do not create a new product domain only because a capability has its own track.
Capabilities are cross-domain workflows; product domains are ownership
boundaries.

## Implemented Capability Groups

1. Declaration UX, discovery, traits, tags, and runner plan.
2. Package workflow over discovered declarations, including generated hosts for
   library and test targets and one host process per step.
3. Runner policy depth: fixed iterations and automatic batching by default,
   plus fixed batches and adaptive/min/max-duration opt-in.
4. Report collection, event stream, document schema, baseline, budget, and CI
   verdicts.
5. Dimension-first measurement and Report Dimension curves.
6. Testing/XCTest adapter UX and failure/artifact projection over
   `ReportDocument`.
7. Metrics: wall-clock and CPU time, Swift allocation and reference counting,
   peak memory, and custom metrics.
8. Apple diagnostics: `xctrace` recording and trace attachments.
9. Full-system fixture acceptance.
