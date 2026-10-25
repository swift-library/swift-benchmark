# ``Benchmark``

@Metadata {
  @PageImage(purpose: icon, source: "benchmark-icon", alt: "swift-benchmark logo")
  @PageColor(orange)
}

Declare and run repeatable performance measurements.

## Overview

Benchmark owns declarations, discovery, execution plans, warmup, batching and
measured iterations, and the metrics each sample records: wall-clock and CPU
time, Swift allocations and reference counting, peak memory, and values a
workload records. Each argument produces a measurement row. Report owns
comparisons and exported performance reports.

See the [package usage guide](https://github.com/swift-library/swift-benchmark/blob/master/Documentation/UsageManual.md)
for installation and complete examples.
