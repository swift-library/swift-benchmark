# swift-benchmark

`swift-benchmark` is a Swift performance toolkit for production, test, and CI
performance evidence. Its architecture separates runtime instrumentation from
repeatable measurement:

- `Instruments`: runtime-safe instrumentation for production and test code.
- Instruments macro ergonomics provided through the `Instruments` product.
- `Benchmark`: repeatable workload measurement for test, bench, and CI.
- `Report`: structured performance evidence, baseline comparison, attribution,
  diagnostics, and rendering.
- `Memory`, `BenchmarkTesting`, and `BenchmarkXCTest`: adapter layers over
  Benchmark and Report.

The implemented current scope includes:

1. Instruments-first runtime and macro alignment.
2. Swift-Testing-shaped Benchmark declarations, arguments, traits/tags,
   discovery, runner plans, event streams, fixed/adaptive measurement, and
   structured scale measurement.
3. Report JSON, baseline/budget checks, argument rows and Dimension curves, adapter helpers,
   Memory/allocation evidence, xctrace/Instruments trace evidence, and
   host-backed plus no-host SwiftPM package workflows.

The accepted active architecture is arguments-first: benchmark declarations use
Swift Testing-style `arguments` for parameterized rows. Numeric arguments are
projected into `Benchmark.Scale` for curves, amortized metrics, and
`Report.DimensionCurve` records.

Signpost is not a product domain; it is the Apple backend that should live
behind the Instruments recorder model. Benchmark remains a separate product
domain and should not be folded into the Instruments runtime layer.

## Install

```swift
// Package.swift
.dependencies: [
  .package(
    url: "https://github.com/swift-library/swift-benchmark.git",
    .upToNextMinor(from: "0.1.0")
  ),
],
.targets: [
  .target(
    name: "YourTarget",
    dependencies: [
      .product(name: "Instruments", package: "swift-benchmark"),
      .product(name: "Benchmark", package: "swift-benchmark"),
      .product(name: "Report", package: "swift-benchmark"),
    ]
  ),
  .testTarget(
    name: "YourPackageTests",
    dependencies: [
      .product(name: "Benchmark", package: "swift-benchmark"),
      .product(name: "BenchmarkTesting", package: "swift-benchmark"),
    ]
  )
]
```

To enable the SwiftPM command plugin from a package that depends on
`swift-benchmark`, run:

```bash
swift package benchmark list
```

## Current Status

The current Benchmark/Report/package workflow is production-usable for the
core paths:

- Tests-first `@Suite(.benchmark...)` / `@Test(.benchmark...)` authoring.
- Native library-target `@BenchmarkSuite` / `@Benchmark` authoring.
- No-host `swift package benchmark list/run/check/trace` for supported package
  declarations.
- `ReportDocument` JSON, baselines, budgets, argument rows/curves, timeline
  attribution, memory/allocation evidence, xctrace attachments, and stable CI
  exit semantics.

Known boundaries are explicit: executable-only declarations use advanced
`--host`, `private`/`fileprivate` Testing bridge declarations are diagnosed,
ambiguous multi-numeric argument rows do not infer a curve key, and MetricKit is
future optional production diagnostics evidence.

### Discovery Backend

The default package workflow uses the stable discovery backend:

```bash
swift package benchmark list
swift package benchmark run
```

It does not build or link the SwiftSyntax discovery backend and does not require
extra SwiftPM flags. Maintainers can explicitly compare the opt-in SwiftSyntax
backend by building its isolated tool and selecting it with environment
variables:

```bash
BIN=$(swift build --disable-experimental-prebuilts --target BenchmarkSyntaxDiscoveryTool --show-bin-path)

SWIFT_BENCHMARK_DISCOVERY_BACKEND=swiftsyntax \
SWIFT_BENCHMARK_SWIFTSYNTAX_TOOL_PATH="$BIN/BenchmarkSyntaxDiscoveryTool" \
swift package --disable-experimental-prebuilts benchmark list
```

`swiftsyntax` mode is a discovery implementation switch only; both backends
emit the same `BenchmarkDiscoveryPlan` shape and feed the same
`BenchmarkRunner` / `ReportDocument` pipeline.

## Quick Start

Recommended workflow: keep benchmark declarations in your test target, mark
them with Swift Testing benchmark traits, and run performance measurement
through `swift package benchmark`.

```swift
import Benchmark
import BenchmarkTesting
import Testing

extension Tag {
  @Tag static var parser: Self
}

@Suite(
  "ParserPerformance",
  .benchmark(configuration: .init(warmup: .iterations(2), iterations: .iterations(20))),
  .tags(.parser)
)
struct ParserPerformanceTests {
  @Test("Parse document", arguments: [1, 2, 4, 8])
  func parseDocument(scale: Int) throws {
    let document = makeDocument(scale: scale)
    try blackHole(parse(document))
  }
}
```

Run them through the package plugin:

```bash
swift package benchmark list
swift package benchmark run --tag parser --format json --output .build/benchmark-report.json
```

The benchmark command discovers supported `@Suite(.benchmark...)` and
`@Test(.benchmark...)` declarations in test targets, generates the bridge, and
runs them through `BenchmarkRunner`. Plain `swift test` remains a correctness
test workflow; use `swift package benchmark` for warmup, measured iterations,
Report JSON, baselines, budgets, and diagnostics.

Use a baseline in CI:

```bash
swift package benchmark baseline write \
  --input .build/benchmark-report.json \
  --output Benchmarks/baseline.json

swift package benchmark check \
  --tag parser \
  --baseline Benchmarks/baseline.json \
  --baseline-metric p95 \
  --threshold-percent 10
```

`check` exits nonzero when regression, budget, execution, configuration, or
required-diagnostic failures occur. A zero exit means the run is usable for CI:
no failing regression or budget verdict was produced.

Add explicit instrumentation in the workload when you want Report timeline
drill-down:

```swift
import Instruments

#span("Parser.normalize") {
  normalize(markdown)
}
```

Then run with timeline capture:

```bash
swift package benchmark run --tag parser --timeline --format json --output .build/report.json
```

The report correlates those business spans and events under the measured
benchmark iteration/sample. On Apple platforms, the same instrumentation can
also continue through Signpost/xctrace for deeper Instruments analysis.

## Best Practices

- Put day-to-day benchmark workloads in `Tests` and run them separately with
  `swift package benchmark`.
- Use tags to define fast local subsets and slower CI/release gates.
- Use Swift Testing-style `arguments` for input rows. Integer arguments, and
  integer-backed `RawRepresentable` arguments, produce `Benchmark.Scale` curves.
- Treat `ReportDocument` JSON as the contract for agents, dashboards, and
  downstream renderers.
- Use native `@BenchmarkSuite` / `@Benchmark` when a benchmark should live in a
  library target or must not run as an ordinary Swift Testing test.
- Keep instrumentation explicit with `#span`, `@Span`, or `@Instrumented`; the
  benchmark macro does not insert spans automatically. Function and initializer
  body spans can appear in `ReportDocument` attribution when run with
  `--timeline`.

## Usage Manual

The README is intentionally the quick-start path. The complete usage manual is
[Documentation/UsageManual.md](Documentation/UsageManual.md). It covers:

- Tests-first BenchmarkTesting authoring.
- Native `@BenchmarkSuite` / `@Benchmark` authoring.
- Argument and scale input-size measurements.
- CLI/plugin commands for list, run, check, baseline, diff, trace, and render.
- `ReportDocument` JSON, baselines, budgets, argument rows, and Dimension curves.
- Memory/allocation evidence, xctrace/Instruments trace evidence, XCTest
  adapters, advanced `--host` workflows, and troubleshooting boundaries.

Best-practice default: write benchmark workloads in `Tests` with
`@Suite(.benchmark...)` / `@Test(.benchmark...)`, then run them separately with
`swift package benchmark`. Use native `@BenchmarkSuite` when you need
library-target benchmark declarations, private same-scope macro discovery, or a
benchmark suite that should never be seen by the ordinary Swift Testing runner.

## Runtime Instrumentation

`SignpostRecorder` owns the Apple Signpost backend. Public Instruments APIs
describe spans, events, recorders, tokens, and attributes.

## Documentation

- `Documentation/UsageManual.md`: complete user manual for API, CLI, CI, diagnostics,
  adapters, and advanced workflows.
- `Documentation/Architecture/ProductDomains.md`: product-domain map.
- `Documentation/Architecture/Instruments.md`: Instruments architecture source of truth.
- `Documentation/Architecture/Benchmark.md`: Benchmark architecture source of truth and
  runner scope.
- `Documentation/Architecture/Dimension.md`: Dimension-first measurement architecture.
- `Documentation/Architecture/Report.md`: Report, baseline, attribution, diagnostics,
  and renderer architecture.
- `Documentation/Migrations/SignpostToInstruments.md`: migration record.
- `Documentation/Reference/InstrumentsAlignmentChecklist.md`: implementation checklist
  for the Instruments alignment pass.
- `Documentation/Reference/BenchmarkCompletionChecklist.md`: implementation checklist
  for the Benchmark implementation goal.

## Requirements

Current package settings:

- iOS 18+
- macOS 15+
- Swift tools 6.0+

The supported system window covers the three most recent stable major releases
for each declared Apple platform: currently iOS 18, 26 and 27, and macOS 15, 26
and 27. Compiler requirements are maintained separately.

[Versioning and release policy](Documentation/Architecture/VersioningAndRelease.md)
describes compatibility and maintenance.

Inspect the installed CLI or plugin version with `swift-benchmark-cli --version`
or `swift package benchmark --version`.

## License

Apache License 2.0 with the Swift Runtime Library Exception
(`Apache-2.0 WITH Swift-exception`). See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Repository Policy

- Local commit hook path: `.githooks`
- Commit policy CI workflow: `.github/workflows/commit-message.yml`
- Contributor policy: see `CONTRIBUTING.md`.
- Architecture direction: see `Documentation/Architecture/Instruments.md`.

- Repository type: `swift-package`.
