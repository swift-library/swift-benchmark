# swift-benchmark Usage Manual

This manual is the complete user-facing guide for using `swift-benchmark`.
`README.md` stays focused on install, quick start, and the recommended path.

The recommended default is Tests-first authoring: put benchmark workloads in
your test target with Swift Testing syntax, then run them separately through
`swift package benchmark`. That keeps fixtures, imports, and package layout
familiar while the benchmark command owns warmup, measured iterations, reports,
baselines, diagnostics, and CI exit codes.

## Installation

```swift
// Package.swift
.dependencies: [
  .package(url: "https://github.com/swift-library/swift-benchmark.git", from: "0.1.0"),
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

Only add products to a target that uses them directly:

- `BenchmarkTesting` belongs in test targets that use
  `@Suite(.benchmark...)` or `@Test(.benchmark...)`.
- `Benchmark` belongs where benchmark declarations or `blackHole` are used.
- `Instruments` belongs where `#span`, `#event`, `@Span`,
  `@Instrumented`, or `@InstrumentedMembers` are used.
- `Report` belongs where code reads or writes `ReportDocument`,
  baselines, budgets, diagnostics, or host workflows.

## Recommended Workflow

### 1. Write Benchmarks In Tests

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
  @Test("Parse document")
  func parseDocument() throws {
    let document = makeDocument()
    try blackHole(parse(document))
  }
}
```

`@Suite(.benchmark...)` gives every supported test in that suite a benchmark
configuration. A single test can opt in from a normal suite:

```swift
@Suite("Parser")
struct ParserTests {
  @Test(
    "Tokenize",
    .benchmark(configuration: .init(warmup: .iterations(1), iterations: .iterations(10))),
    .tags(.parser)
  )
  func tokenize() throws {
    try blackHole(tokenizer.tokenize(input))
  }
}
```

Plain `swift test` remains a correctness workflow. `swift package benchmark`
is the performance runner: it discovers benchmark-marked tests, generates the
bridge, and runs them through `BenchmarkRunner` and `ReportDocument`.

### 2. Discover And Run

```bash
swift package benchmark list
swift package benchmark run --format console
swift package benchmark run --tag parser --format json --output .build/benchmark-report.json
```

Use tags for local focus and CI selection:

```bash
swift package benchmark list --tag parser --format json
swift package benchmark run --tag parser --quiet --format json --output .build/parser-report.json
```

### Discovery Backend Selection

The default package workflow uses the stable discovery backend:

```bash
swift package benchmark list
swift package benchmark run
```

This path is the production default. It does not build or link the SwiftSyntax
discovery backend and does not require extra SwiftPM flags.

For maintainer A/B validation, build the isolated SwiftSyntax discovery tool and
select it explicitly:

```bash
BIN=$(swift build --disable-experimental-prebuilts --target BenchmarkSyntaxDiscoveryTool --show-bin-path)

SWIFT_BENCHMARK_DISCOVERY_BACKEND=swiftsyntax \
SWIFT_BENCHMARK_SWIFTSYNTAX_TOOL_PATH="$BIN/BenchmarkSyntaxDiscoveryTool" \
swift package --disable-experimental-prebuilts benchmark list
```

Supported backend modes:

- `stable` or unset: run the production self-contained scanner.
- `swiftsyntax`: require `SWIFT_BENCHMARK_SWIFTSYNTAX_TOOL_PATH` and fail
  loudly if the tool cannot run.
- `auto`: try the syntax tool when a path is provided, warn on failure, then
  fall back to the stable scanner.

Both backends emit the same internal discovery plan shape and feed the same
generated host, `BenchmarkRunner`, and `ReportDocument` pipeline. The
SwiftSyntax path exists to validate AST-based source discovery without making
ordinary users depend on SwiftPM's current source-built SwiftSyntax plugin path.

### 3. Gate CI With Baselines

Create or refresh a baseline from a known-good report:

```bash
swift package benchmark run --tag parser --format json --output .build/parser-report.json
swift package benchmark baseline write \
  --input .build/parser-report.json \
  --output Benchmarks/parser-baseline.json
```

Check future runs against that baseline:

```bash
swift package benchmark check \
  --tag parser \
  --baseline Benchmarks/parser-baseline.json \
  --baseline-metric p95 \
  --threshold-percent 10 \
  --format json \
  --output .build/parser-check.json
```

`check` exits nonzero for invalid configuration, benchmark execution failure,
regression failure, budget failure, or required diagnostic failure. Exit code
`0` covers success, no regression, and improvement.

### 4. Gate CI With Budgets

Use a single-run budget when no saved baseline is desired:

```bash
swift package benchmark run \
  --tag parser \
  --budget p95:5000000 \
  --format json \
  --output .build/parser-budget-report.json
```

Case-specific budgets use `suite:case:metric:nanoseconds`:

```bash
swift package benchmark check \
  --tag parser \
  --baseline Benchmarks/parser-baseline.json \
  --case-budget "ParserPerformance:Parse document:p95:5000000" \
  --format json
```

Supported metric selectors include `mean`, `median`, `p90`, `p95`, and `p99`.

## Native Benchmark Declarations

Use native `@BenchmarkSuite` / `@Benchmark` when benchmark declarations should
live in a library target, when same-scope macro discovery is required, or when
the workload should never be seen by the ordinary Swift Testing runner.

```swift
import Benchmark

@BenchmarkSuite(
  "Parser",
  .tag("parser"),
  .configuration(.init(warmup: .iterations(2), iterations: .iterations(20)))
)
struct ParserBenchmarks {
  @Benchmark("Parse document")
  func parseDocument() throws {
    try blackHole(parser.parse(input))
  }

  @Benchmark("Tokenize", .tag("fast"))
  func tokenize() {
    blackHole(tokenizer.tokenize(input))
  }
}
```

For library-target declarations, the package plugin discovers generated
benchmark metadata without requiring users to maintain Provider/Probe files or
a manual host.

Executable-only declarations are an advanced boundary. Use `--host` or move
the declaration into a library/test target for ordinary no-host package
workflow support.

## Argument And Scale Measurements

Use `arguments` when a benchmark should produce one row per input. Integer
arguments, and `RawRepresentable` arguments backed by an integer raw value,
also produce a `Benchmark.Scale` key for curves and amortized metrics:

```swift
@BenchmarkSuite("Parser")
struct ParserBenchmarks {
  @Benchmark("Parse by size", arguments: [10, 100, 1_000])
  func parseBySize(_ byteCount: Int) throws {
    let input = makeInput(byteCount: byteCount)
    try blackHole(parse(input))
  }
}
```

The same shape works in Swift Testing suites:

```swift
@Suite(.benchmark(configuration: .init(warmup: .iterations(2), iterations: .iterations(20))))
struct ParserBenchmarks {
  @Test("Parse fixtures", arguments: ["small.md", "large.md"])
  func parseFixture(_ fixture: String) throws {
    try blackHole(parse(loadFixture(fixture)))
  }
}
```

Each argument value becomes one `Benchmark.Measurement.Row`. Ordinary
benchmarks produce one row with `size == nil`. Argument setup runs outside the
measured iterations; measured samples capture only the workload for that row.
String/file/object arguments produce rows without numeric curves.

Report projects measurement rows into:

- row metrics such as mean, median, p90, p95, and p99,
- baseline and budget verdicts for selected metrics,
- `Report.DimensionCurve` records,
- `amortized` values where selected metric is divided by
  `Benchmark.Scale.rawValue`.

The older `.dimension(sizes:)` spelling remains a compatibility authoring path
for native benchmarks and lowers to `Benchmark.Scale` rows.

## ReportDocument

`ReportDocument` is the durable machine-readable truth:

```text
@BenchmarkSuite / @Benchmark / @Suite(.benchmark...) / @Test(.benchmark...)
  -> _BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> BenchmarkRunner
  -> Benchmark.Event.Stream
  -> ReportRecorder / ReportBuilder
  -> ReportDocument
```

`ReportDocument` can contain:

- run metadata,
- suite/case identities and tags,
- source locations,
- raw samples,
- `Report.Measurement` rows and derived metrics,
- baseline comparisons,
- budget comparisons,
- structured verdict causes,
- Dimension curves,
- timeline attribution,
- diagnostics,
- attachments such as trace artifacts.

JSON is the stable exchange format:

```bash
swift package benchmark run --tag parser --format json --output .build/report.json
swift package benchmark render --input .build/report.json --format console
swift package benchmark render --input .build/report.json --format markdown --output .build/report.md
swift package benchmark render --input .build/report.json --format speedscope --output .build/report.speedscope.json
```

HTML, dashboards, and richer presentations should consume `ReportDocument`
JSON. Swift library code owns data shape and evidence contracts, not hardcoded
presentation authoring.

## CLI And Plugin Commands

The SwiftPM plugin is the normal package workflow:

```bash
swift package benchmark list [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json]
swift package benchmark run [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json|markdown|speedscope] [--output <path>]
swift package benchmark check --baseline <baseline.json> [--baseline-metric mean|median|p90|p95|p99] [--threshold-percent <n>|--threshold-ns <n>]
swift package benchmark trace [same options as run] [--xctrace-output <path>] [--xctrace-template <name>]
swift package benchmark baseline write --input <report.json> --output <baseline.json>
swift package benchmark baseline update --input <report.json> --output <baseline.json>
swift package benchmark baseline check --input <report.json> --baseline <baseline.json>
swift package benchmark diff --input <report.json> --baseline <baseline.json> --format json
swift package benchmark render --input <report.json> --format console|json|markdown|speedscope
```

Advanced/debug host-backed CLI usage is available through the executable:

```bash
swift run swift-benchmark-cli run \
  --host .build/debug/ParserBenchmarkHost \
  --case "Parse document" \
  --format json
```

The package plugin delegates execution to `BenchmarkCLI` after discovery and
host generation. `BenchmarkPlugin` is orchestration; `BenchmarkDiscoveryTool`
and `_BenchmarkDiscoveryCore` own package discovery and generated bridge/host
sources.

## Diagnostics And Traces

Timeline attribution captures the Benchmark/Instruments execution path:

```bash
swift package benchmark run \
  --tag parser \
  --timeline \
  --format json \
  --output .build/report-with-timeline.json
```

When the benchmark workload calls `#span`, `#event`, `@Span`, or
`@Instrumented`, timeline capture transparently records those business spans
under the measured benchmark iteration:

```swift
import Instruments

#span("Parser.normalize") {
  normalize(markdown)
}

#span("Parser.parse") {
  parse(markdown)
}
```

The resulting `ReportDocument` contains the measured sample, the
`BenchmarkIteration` root span, child business spans/events, and span timing
summaries. This does not read OSLog or Console output. Report JSON is the
structured drill-down truth; Signpost/xctrace remains the Apple platform asset
for deeper Instruments analysis.

Attach an existing Instruments trace:

```bash
swift package benchmark run \
  --tag parser \
  --trace .build/parser.trace \
  --format json \
  --output .build/report-with-trace.json
```

Require a trace attachment and fail when it is unavailable:

```bash
swift package benchmark run \
  --tag parser \
  --required-trace .build/parser.trace \
  --format json
```

Record a trace through `xcrun xctrace`:

```bash
swift package benchmark trace \
  --tag parser \
  --xctrace-output .build/parser.trace \
  --xctrace-template "Time Profiler" \
  --format json \
  --output .build/report-with-xctrace.json
```

The report stores trace attachment provenance and command metadata. It does
not parse private `.trace` internals as a stable API.

MetricKit is future optional production diagnostics evidence. It is not part
of the current benchmark acceptance path and should not be treated as a
deterministic per-iteration metric source.

## Memory And Allocation Evidence

Memory/allocation evidence is Report-scoped. Current built-in concepts include:

- Darwin resident memory sampling where available,
- manual memory/allocation snapshots,
- allocation regression summaries,
- provider/profiler extension points,
- file descriptor and resource leak checks,
- explicit diagnostic states: measured, not configured, unavailable, and
  failed.

Unsupported platform metrics report structured `unavailable` states instead of
fake zero values. Required diagnostics can fail a run.

## Instruments Runtime

Use Instruments for production-safe spans and events:

```swift
import Instruments

#span("BuildIndex") {
  buildIndex()
}

#event("CacheMiss")

@Instrumented
func openProject() async throws -> Project {
  ...
}

@Span("BuildIndex")
func buildIndex() throws -> Index {
  ...
}

@Span("Store.init(path:)")
init(path: String) {
  ...
}

@InstrumentedMembers
struct Store {
  init(path: String) {
    ...
  }

  func load() throws -> Item {
    ...
  }
}
```

`#span` records duration, `#event` records a point-in-time marker, and
function/initializer body macros preserve return values, initializer semantics,
thrown errors, and async behavior where supported. `@Instrumented` initializer
names use `Type.init(labels:)`; `@InstrumentedMembers` applies the same naming
to eligible initializers declared directly in the annotated type or extension.
Signpost is the Apple backend behind the Instruments recorder model, not a
public product domain.

## Swift Testing Bridge Boundaries

Supported:

- `@Suite(.benchmark...)` applies benchmark configuration to supported tests in
  that suite.
- `@Test(.benchmark...)` opts a single test into benchmark discovery or
  refines suite defaults.
- `@Test(arguments:)` and `@Benchmark(arguments:)` produce benchmark rows when
  the declaration is benchmark-enrolled.
- Swift Testing tags flow into benchmark plan filtering and report metadata.
- Supported bridge cases run through `BenchmarkRunner`, not the Swift Testing
  runner.

Diagnosed boundaries:

- `private` and `fileprivate` benchmark-marked tests are not supported in the
  pure generated bridge path. Use `internal`, or use native
  `@BenchmarkSuite` / `@Benchmark` in the same source scope.
- Unsupported argument shapes fail with explicit diagnostics.
- Unsupported declarations fail with explicit diagnostics rather than being
  silently skipped.
- Ordinary `@Test` declarations without `.benchmark` are ignored by the
  benchmark command.

`BenchmarkTestingAdapter` can project `ReportDocument` verdicts into Swift
Testing issues when public Testing APIs are available. The adapter is a sink;
Benchmark core remains independent from the Testing runtime.

## XCTest And Advanced Hosts

`BenchmarkXCTestAdapter` is for existing XCTest workflows. It can attach
structured report JSON and project verdict causes through XCTest failures and
attachments. XCTest remains an adapter sink; Benchmark and Report remain the
truth.

Manual hosts are advanced/debug flows:

```swift
import Report

@main
struct ParserBenchmarkHost {
  static func main() async throws {
    try await BenchmarkHost.run(discoveries: [ParserBenchmarks.self])
  }
}
```

```bash
swift run swift-benchmark-cli run \
  --host .build/debug/ParserBenchmarkHost \
  --case "Parse document" \
  --format json
```

Ordinary package workflows should not require this host for library-target
`@BenchmarkSuite` declarations or supported test-target BenchmarkTesting
declarations.

## Best Practices

- Prefer Tests-first authoring for application and library teams.
- Keep benchmark bodies deterministic and explicit about setup.
- Use `blackHole` for values that would otherwise be optimized away.
- Use tags to separate fast local benchmarks from slower CI or release gates.
- Use fixed iterations by default; opt into adaptive or duration policies only
  when the workload needs it.
- Use `arguments` for input rows; integer arguments produce `Benchmark.Scale`
  curves.
- Store baselines under a reviewed path such as `Benchmarks/*.json`.
- Treat `ReportDocument` JSON as the contract for agents, dashboards, and
  downstream renderers.
- Keep instrumentation explicit with `#span`, `@Span`, or `@Instrumented`; the
  benchmark macro does not automatically insert spans. Function and initializer
  body spans can be correlated into `ReportDocument` when run with `--timeline`.
- Use native `@BenchmarkSuite` when the workload must not be an ordinary Swift
  Testing test.

## Troubleshooting

- If `swift package benchmark list` finds no cases, confirm the target depends
  on `BenchmarkTesting` for test-target declarations or `Benchmark` for native
  declarations.
- If a Testing benchmark is diagnosed as private, change it to `internal` or
  use native `@BenchmarkSuite` / `@Benchmark`.
- If `@Test(arguments:)` is diagnosed, check for unsupported parameter shapes
  such as ambiguous argument counts.
- If an executable-only declaration is not discovered by no-host package
  workflow, move it to a library/test target or use `--host`.
- If an Apple diagnostic is required but unavailable, the command should fail
  with a diagnostic-unavailable error instead of producing fake data.
- If a report renderer is not enough, consume `ReportDocument` JSON and build a
  separate renderer/template outside the core Swift library.
