# Memory Architecture

## Scope / Purpose

This document owns Memory and allocation diagnostics. Memory enriches benchmark
reports with resident-memory and allocator evidence. It does not define
Benchmark runner semantics and does not belong inside Instruments runtime.

## Current Implementation Status

Current source implements explicit diagnostic states, one-shot resident-memory
sampling, manual memory metric snapshots, manual allocation snapshots, net/peak
allocation fields, leak-tolerance verdicts, allocation regression analysis with
preheat/repeated-run aggregation, and file-descriptor/resource leak checks.
Platform-specific automatic allocator hooks and long-running resident-memory
sampling remain extension points behind the same provider/profiler states.

## Metric Dimensions

Resident memory and allocator metrics are separate dimensions.

Resident memory:

- RSS,
- physical/resident bytes,
- peak resident bytes where available.

Allocator metrics:

- allocated bytes,
- allocation count,
- deallocation count,
- net allocations,
- net bytes,
- peak allocated bytes,
- leak/tolerance data,
- profiler/histogram evidence where feasible.

## Provider States

Providers must report explicit states:

- `measured`,
- `notConfigured`,
- `unavailable(reason:)`,
- `failed(reason:)`.

Unsupported metrics must never be reported as zero.

## Source Use

Architecture truth records local provider/profiler requirements rather than
implementation-source details. Allocation and resource-regression behavior should
preserve:

- preheat,
- repeated runs,
- min/median aggregation,
- resource regression checks,
- platform caveats.

## Integration

Memory evidence enters through Report diagnostics and adapter verdicts:

```text
BenchmarkRunner
  -> Memory provider/profiler
  -> DiagnosticMetric / DiagnosticAttachment
  -> ReportDocument
  -> CLI / Testing / XCTest verdicts
```

Memory/allocation must remain compatible with Swift Testing adapters:

- budget failures project to Testing issues,
- artifacts attach through adapter sinks,
- source-location context comes from benchmark declarations or adapter call
  sites.

## Acceptance Evidence

- Provider/profiler tests.
- Platform-gated resident-memory tests.
- Allocation/deallocation/net/peak metric tests.
- Leak/tolerance tests.
- Unavailable/notConfigured/failed state tests.
- Testing/XCTest adapter verdict tests.
