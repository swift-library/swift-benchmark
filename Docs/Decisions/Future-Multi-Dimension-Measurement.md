# Future Multi-Dimension Measurement

## Status

Proposal only. Not part of the implemented single-Dimension architecture.

## Context

The accepted active architecture is single-Dimension:

```text
Benchmark.Dimension.Size
  -> Benchmark.Measurement.Row(size:samples:)
  -> Report.Measurement.Row.metrics
  -> Report.DimensionCurve
```

This keeps the user model and implementation tractable while preserving the
Apple-aligned input-size mental model.

Future workloads may need more than one measurement dimension, for example
input bytes, row count, column count, concurrency, or batch size. Those needs
should not force the current plan to introduce a coordinate model before the
single-Dimension workflow is proven.

## Future Design Space

Possible future concepts:

- multiple named Dimensions on one benchmark case,
- coordinate generators that produce inputs from a tuple of Dimension values,
- rows-by-columns or other derived size formulas,
- facet records for comparing one selected Dimension while holding another
  constant,
- heatmap-friendly report projections.

## Current Non-Goals

- no public multi-Dimension API in the current implementation pass,
- no Cartesian product generator in current `BenchmarkRunner.Plan`,
- no heatmap or facet Report schema in the current stable contract,
- no replacement of `Benchmark.Measurement.Row(size:samples:)` as the
  single-Dimension truth.

## Open Questions

- Should coordinates be a fixed tuple type, a named-value dictionary, or a
  generated struct?
- Which Dimension is the primary size for amortized metrics when multiple
  dimensions exist?
- Should derived size be stored in Benchmark measurement or only in Report?
- How should baseline and budget selectors address one Dimension, many
  Dimensions, or a derived coordinate?

These questions are deferred until the single-Dimension implementation and
Report projection are complete.
