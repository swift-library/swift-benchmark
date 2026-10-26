# ``BenchmarkXCTest``

@Metadata {
  @PageImage(purpose: icon, source: "benchmarkxctest-icon", alt: "swift-benchmark logo")
  @PageColor(orange)
}

Run benchmark measurements from XCTest.

## Overview

This adapter measures benchmark suites from XCTest, attaches the structured
report and reports its verdicts as failures. It keeps test-framework
integration separate from the measurement runner and report formats.

See the [package usage guide](https://github.com/swift-library/swift-benchmark/blob/master/Documentation/UsageManual.md)
for installation and complete examples.
