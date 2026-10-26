# swift-benchmark Usage Manual

This manual is the complete user-facing guide for using `swift-benchmark`.
`README.md` stays focused on install, quick start, and the recommended path.

The recommended default is Tests-first authoring: put benchmark workloads in
your test target with Swift Testing syntax, then run them separately through
`swift package benchmark`. That keeps fixtures, imports, and package layout
familiar while the benchmark command owns warmup, batching, measured samples,
metrics, reports, baselines, and CI exit codes.

## Installation

```swift
// Package.swift
.dependencies: [
  .package(
    url: "https://github.com/swift-library/swift-benchmark.git",
    .upToNextMinor(from: "0.2.0")
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

Only add products to a target that uses them directly:

- `BenchmarkTesting` belongs in test targets that use
  `@Suite(.benchmark...)` or `@Test(.benchmark...)`.
- `Benchmark` belongs where benchmark declarations, `blackHole`, or
  `Benchmark.record(_:for:)` are used.
- `Instruments` belongs where `#span`, `#event`, `@Span`, `@Instrumented`,
  `@InstrumentedMembers`, or the runtime recorder API are used.
- `Report` belongs where code reads or writes `ReportDocument`, baselines, or
  budgets, and in an executable passed to the CLI with `--host`.

### Instruments Without swift-syntax

The Instruments macros are compiled by a macro target that builds swift-syntax.
The package's `Macros` trait, enabled by default, declares them. Production
code that only needs the runtime API can drop the trait:

```swift
.package(
  url: "https://github.com/swift-library/swift-benchmark.git",
  .upToNextMinor(from: "0.2.0"),
  traits: []
),
```

Without `Macros`, Instruments offers the recorder API alone:

```swift
import Instruments

let index = Instruments.current.span("BuildIndex") {
  buildIndex()
}
Instruments.current.event("CacheMiss")
```

SwiftPM merges each package's traits across the whole dependency graph. If any
package in the graph depends on swift-benchmark with its default traits, the
macros and swift-syntax are built for everyone; dropping the trait saves the
build only when no package in the graph enables it. Swift 6.3 builds the macro
target and swift-syntax even without the trait; the saving needs Swift 6.4 or
later.

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

`@Suite(.benchmark...)` enrolls every supported test in that suite, and nested
suites inherit it. A single test can opt in from a normal suite, and its
configuration overrides the suite's:

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

Plain `swift test` remains a correctness workflow and runs each test once.
`swift package benchmark` is the performance runner: it discovers
benchmark-enrolled tests, generates a bridge that declares them as benchmarks,
and measures them through `BenchmarkRunner`.

### 2. Discover And Run

```bash
swift package benchmark list
swift package --configuration release benchmark run --format console
swift package --configuration release --allow-writing-to-directory .build benchmark run --tag parser --format json --output .build/benchmark-report.json
```

Use tags for local focus and CI selection:

```bash
swift package benchmark list --tag parser --format json
swift package --configuration release --allow-writing-to-directory .build benchmark run --tag parser --quiet --format json --output .build/parser-report.json
```

With Swift 6.3 (Xcode 26), pass `--disable-experimental-prebuilts` to every
plugin command, for example
`swift package --disable-experimental-prebuilts benchmark list`. SwiftPM 6.3
cannot build the plugin's SwiftSyntax tool beside macros built from SwiftSyntax
prebuilts and fails with `no such module 'SwiftParser'`; with the flag,
SwiftSyntax builds from source, which makes the first build slower. Swift 6.4
needs no flag.

The plugin parses the package's Swift sources with SwiftSyntax to find
declarations; it does not run the tests to discover them. Each listed step is
one case, or one argument row or Dimension size of a case.

The plugin builds only the targets that declare benchmarks, with their
dependencies, so unrelated targets such as UI tests are not compiled. A
release run in a package that declares benchmarks in any test target is the
exception, whatever the run selects: SwiftPM compiles test targets for testing
in release only when it builds all of them, so that run builds every test
target. Declaring the package's benchmarks in library targets avoids it.

### 3. Gate CI With Baselines

Create or refresh a baseline from a known-good report:

```bash
swift package --configuration release --allow-writing-to-directory .build benchmark run --tag parser --format json --output .build/parser-report.json
swift package --allow-writing-to-directory Benchmarks benchmark baseline write \
  --input .build/parser-report.json \
  --output Benchmarks/parser-baseline.json
```

Check future runs against that baseline:

```bash
swift package --configuration release --allow-writing-to-directory .build benchmark check \
  --tag parser \
  --baseline Benchmarks/parser-baseline.json \
  --statistic p95 \
  --threshold 10% \
  --format json \
  --output .build/parser-check.json
```

Every metric that both the run and the baseline measured is compared, row by
row: each argument row or Dimension size is compared with the same row of the
baseline. Metrics not compared by default, such as the operating system metrics
described under [Metrics](#metrics), are compared only when a threshold names
them. An argument row is identified by the descriptions of its values, not by
its position, so reordering arguments keeps rows matched; give argument values
distinct descriptions, because rows whose values describe the same are numbered
in order. A metric regresses when it moves past the threshold in its worse
direction, which is up for times, counts and bytes, and down for a custom metric
declared `.higherIsBetter`, and the change is significant: each comparison
carries a 95% confidence interval of the difference, estimated by resampling
both runs' samples, and a change whose interval includes zero can be noise, so
it passes. The interval is reproducible: the same samples always give the same
interval. Metrics with one value per row, such as the heap and Swift allocation
counts, have no interval, so their threshold alone judges them.

`check` exits `0` when nothing regressed or exceeded a budget, `20` for a
regression or budget failure, `2` for invalid options, configuration or input
files, including configuration the host rejects, `3` when a host fails, and
`30` when a required trace is missing or recording one fails. It
refuses to judge a debug build, because debug times and counts do not
represent release performance; pass `--allow-debug` to check one anyway.

### 4. Gate CI With Budgets

Use a budget when no saved baseline is desired:

```bash
swift package --configuration release --allow-writing-to-directory .build benchmark run \
  --tag parser \
  --budget wallClock:p95:5ms \
  --budget swiftAllocations:median:10 \
  --format json \
  --output .build/parser-budget-report.json
```

Case-specific budgets use `suite:case:metric:statistic:amount`:

```bash
swift package --configuration release benchmark check \
  --tag parser \
  --baseline Benchmarks/parser-baseline.json \
  --case-budget "ParserPerformance:Parse document:wallClock:p95:5ms" \
  --format json
```

A budget is an upper limit for metrics where lower is better and a lower limit
for metrics where higher is better.

### Comparison Options

- `--statistic min|max|mean|median|standardDeviation|p90|p95|p99` chooses the
  statistic baseline comparisons use; the default is `median`.
- `--threshold <n>%` sets the relative threshold for every metric; the default
  is `10%`. `--threshold <metric>=<n>%` or `--threshold <metric>=<amount>`
  overrides it for one metric, with an absolute amount in the metric's unit.
- `--budget <metric>:<statistic>:<amount>` and
  `--case-budget <suite>:<case>:<metric>:<statistic>:<amount>` add budgets.

Amounts are plain numbers in the metric's unit. Built-in metrics also accept
`ns`, `us`, `ms` and `s` for times and `B`, `KB`, `MB`, `GB`, `KiB`, `MiB` and
`GiB` for bytes. Custom metrics take plain numbers only.

### Warnings

Reports carry warnings that do not change verdicts but say when a comparison
deserves less trust:

- the run measured a debug build;
- the baseline was recorded under different conditions: platform, OS version,
  architecture, device model, Swift version or build configuration;
- a compared row has fewer than five timed samples;
- a compared metric varies, in this run or in the baseline, as much as its
  threshold allows: its coefficient of variation reaches a relative threshold,
  or its standard deviation reaches an absolute one;
- at least a tenth of a compared metric's values, out of five or more, lie far
  outside the rest, which usually means other work disturbed the run.

Statistics count outliers for every metric: `mildOutliers` beyond 1.5
interquartile ranges outside the quartiles, `severeOutliers` beyond 3.

The console format prints warnings after the results, and JSON lists them in
`warnings` for the run and for each case.

## Metrics

A step records these metrics, each reported per call of the workload, where
the platform and runtime provide them; the notes after the table say when:

| Metric | Unit | Measured |
| --- | --- | --- |
| `wallClock` | nanoseconds | Elapsed time of each timed sample |
| `cpuTime` | nanoseconds | User plus system CPU time of the process during each timed sample |
| `instructions` | count | Instructions retired during each timed sample |
| `cycles` | count | Processor cycles during each timed sample |
| `contextSwitches` | count | Context switches of the process; reported, judged only on request |
| `pageFaults` | count | Minor and major page faults of the process; reported, judged only on request |
| `systemCalls` | count | System calls of the process, on Apple platforms; reported, judged only on request |
| `diskReadBytes` | bytes | Bytes read from storage, on macOS and Linux; reported, judged only on request |
| `diskWriteBytes` | bytes | Bytes written to storage, on macOS and Linux; reported, judged only on request |
| `swiftAllocations` | count | Swift runtime heap allocations, in a counting pass after the timed samples |
| `swiftAllocatedBytes` | bytes | Bytes those allocations requested |
| `swiftRetains` | count | Swift strong retains in the counting pass |
| `swiftReleases` | count | Swift strong releases in the counting pass |
| `heapAllocations` | count | Allocations through `malloc` and its relatives, from Swift, C, C++ and Objective-C, in the package workflow's counting process |
| `heapAllocatedBytes` | bytes | Bytes those allocations requested |
| `heapNetAllocations` | count | Allocations minus frees; a steady positive value means each call keeps memory |
| `peakMemory` | bytes | How far the process's memory footprint rose above its level at the start of the step; one value per step |

`instructions` and `cycles` vary far less with machine load than time does,
which makes them a steady regression gate on shared CI machines. Apple
platforms count the whole process; where the hardware counters are unavailable,
as in some virtual machines, the metrics are left out. Linux counts user-mode
instructions of the thread that runs the batch and the threads it creates, so
it records them only for synchronous workloads and only where the kernel allows
the process to open hardware counters.

Context switches, page faults, system calls and disk bytes depend on the rest of
the machine as much as on the code, so they appear in each row's values but
baseline comparisons leave them out. Give one a threshold or a budget to judge
it, for example `--threshold contextSwitches=0`. Runners created in your own
code count these events and the hardware counters unless created with
`countsProcessEvents: false`.

Timing and counting are separate: the timed samples run without the counting
hooks, so hooks cannot slow the times, and a counting pass then runs one more
batch with the hooks installed. The counts include every thread of the
process. On Apple platforms the Swift counts come from the Swift runtime's
instrumentation hooks, in any process.

The package workflow also counts every heap allocation. `swift package
benchmark` builds a small interposer library and measures each step in two
host processes: one times the step, and one that loads the library counts its
allocations in batches of the same size. The library slows every allocation,
so the timing process never loads it. On Linux the same counting process also
records the Swift counts, for the calls compiled code makes into the runtime.
Outside the counting process, such as in tests, the heap metrics are left out,
and on Linux the Swift counts too. The Linux interposer replaces glibc's
allocator, so on a system built on another C library, such as musl, the counting
process records no heap metrics and the run fails. A counting process counts
allocations as the build produces them, so a debug build can count more than a
release build.

To see where the allocations come from, add `--allocation-sites` to `run` or
`check`. The counting process records the call stack of every allocation in one
more batch, and the report lists each row's stacks, most allocations first, up
to 50, with allocations and bytes per call:

```bash
swift package --allow-writing-to-directory .build benchmark run \
  --tag parser --allocation-sites --format speedscope --output .build/allocations.speedscope.json
```

The console and Markdown formats show the top stacks from the first frame
outside the Swift runtime and the system allocator; the speedscope format
opens them as flame graphs weighted by allocations and by bytes. Stacks name
functions from the host's symbol tables; inlined functions appear as their
callers. Recording sites is slower, so it is off unless requested.

`peakMemory` needs a process that measures nothing else, because platforms
report only the highest footprint over the process lifetime. The package
workflow runs every step in a host process of its own and records it there; a
step whose footprint never exceeds the peak the process reached before the step
records no value. Runners created in your own code leave it out unless created
with `recordsPeakMemory: true`.

On Linux, wall-clock and CPU time are always available; metrics the platform
or runtime cannot provide are left out of the samples rather than reported as
zero.

### Custom Metrics

A workload can record its own values. Each sample sums a metric's recorded
values and divides by the number of calls:

```swift
import Benchmark

extension Benchmark.Metric {
  static let parsedBytes = Benchmark.Metric(name: "parsedBytes", unit: .bytes)
  static let throughput = Benchmark.Metric(
    name: "documentsPerSecond", unit: .count, direction: .higherIsBetter)
  static let cacheMisses = Benchmark.Metric(
    name: "cacheMisses", unit: .count, isComparedByDefault: false)
}

@Benchmark("Parse document")
func parseDocument() throws {
  let result = try parse(input)
  Benchmark.record(Double(result.byteCount), for: .parsedBytes)
}
```

A metric is identified by its name. Names of built-in metrics are reserved, and
values recorded under one are ignored. The first descriptor recorded for a name
decides its unit, its direction, and whether baseline comparisons judge it
without a threshold of its own (`isComparedByDefault`, `true` unless given).
Custom metrics appear in statistics, baselines, budgets and thresholds like
built-in ones.

## Batching And Iterations

A sample can time several consecutive calls. By default batching is automatic:
before the timed samples, the runner grows the call count until one batch lasts
1 ms, up to 1,000,000 calls, and reports each sample's values divided by its
batch size. Workloads that take a microsecond or less are therefore timed over
windows long enough for clock resolution not to matter, while slow workloads
run one call per sample.

```swift
BenchmarkConfiguration(
  warmup: .iterations(2),
  iterations: .iterations(20),
  batching: .automatic(targetNanoseconds: 2_000_000, maxBatchSize: 100_000)
)

BenchmarkConfiguration(iterations: .iterations(20), batching: .fixed(1))
```

The default configuration warms up once, measures ten samples and batches
automatically. `--batch-size <n>` fixes the batch size for a run, and
`--warmup`, `--iterations`, `--adaptive`, `--min-iterations`,
`--max-iterations`, `--min-duration-ns` and `--max-duration-ns` override the
other policies. Adaptive duration limits count the whole time of each batch.

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
also produce a `Benchmark.Scale` key for curves and amortized values:

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
measured samples; measured samples capture only the workload for that row.
String/file/object arguments produce rows without numeric curves.

Report projects measurement rows into:

- statistics for each metric: count, min, max, mean, median, standard
  deviation, p90, p95, p99 and outlier counts;
- baseline and budget verdicts for each row;
- `Report.DimensionCurve` records, each with the growth model that best fits
  it once the case has three or more sizes: `complexity` names the model, from
  O(1) to O(n³), its coefficient, and how far the fit is off relative to the
  mean value;
- `amortized` values, a statistic divided by `Benchmark.Scale.rawValue`.

Sizes spread across orders of magnitude, such as 10, 100, 1 000 and 10 000,
tell the growth models apart best.

The `.dimension(sizes:)` trait is another way to declare scale rows for native
benchmarks; it lowers to the same `Benchmark.Scale` rows.

## Per-Call Setup

When every call needs a fresh input, such as an unsorted array for a sort,
make it with `setup:`. The method takes the input as its one `inout`
parameter; `setup` names a static function that makes it, from the row's size
when the benchmark has a `.dimension` trait:

```swift
@BenchmarkSuite("Sorting")
struct SortingBenchmarks {
  @Benchmark("Sort", .dimension(sizes: [100, 10_000]), setup: Self.shuffled)
  func sort(_ values: inout [Int]) {
    values.sort()
  }

  static func shuffled(_ size: Benchmark.Scale) -> [Int] {
    (0..<size.rawValue).shuffled()
  }
}
```

The runner makes every input of a batch before measuring the batch and frees
them after it, so neither the setup nor freeing the inputs is timed or counted,
and values recorded with `Benchmark.record(_:for:)` meanwhile are ignored.
Programmatic benchmarks take the same shape:
`Benchmark("Sort", setup: { (0..<1_000).shuffled() }) { values in values.sort() }`.
A batch holds one input per call in memory at once. Swift Testing bridge
benchmarks have no per-call setup.

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

- run metadata: platform, OS version, architecture, device model, Swift
  version, build configuration and package identity;
- suite/case identities and tags;
- source locations;
- raw samples with their batch sizes and per-call values;
- `Report.Measurement` rows with per-metric statistics;
- baseline and budget comparisons per row and metric;
- structured verdict causes;
- warnings;
- Dimension curves;
- timeline attribution;
- attachments such as trace artifacts.

JSON is the stable exchange format:

```bash
swift package --configuration release --allow-writing-to-directory .build benchmark run --tag parser --format json --output .build/report.json
swift package benchmark render --input .build/report.json --format console
swift package --allow-writing-to-directory .build benchmark render --input .build/report.json --format speedscope --output .build/report.speedscope.json
```

`--format markdown` renders a summary for a pull request comment: the verdict
and warnings, a table of baseline comparisons with their confidence intervals,
or of medians and p95s without a baseline, failed budgets and complexity fits.
Its layout can change between releases; read JSON when a tool needs the data.

A baseline written by an older release fails to load with an error that asks
you to record it again, and decoding a report an older release wrote fails
with an error that asks you to generate it again.

Code that consumes reports can build one in its tests from typed results
instead of writing JSON or report identifiers by hand. `ReportDocument`
computes the identifiers, statistics and verdicts the same way a run does:

```swift
import Benchmark
import Report

let result = BenchmarkResult(
  suiteName: "Parser",
  caseName: "Parse",
  configuration: BenchmarkConfiguration(warmup: .none, iterations: .iterations(2)),
  measurement: Benchmark.Measurement(rows: [
    Benchmark.Measurement.Row(
      id: "small",
      size: nil,
      arguments: [Benchmark.ArgumentValue("small")],
      samples: [
        Sample(iteration: 0, values: [.wallClock: 1_200]),
        Sample(iteration: 1, values: [.wallClock: 1_100]),
      ]
    )
  ])
)
let document = ReportDocument(metadata: .local(id: "run:fixture"), results: [result])
```

HTML, dashboards, and richer presentations should consume `ReportDocument`
JSON. Swift library code owns data shape and report contracts, not hardcoded
presentation authoring.

## CLI And Plugin Commands

The SwiftPM plugin is the normal package workflow:

```bash
swift package benchmark --version
swift package benchmark list [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json]
swift package benchmark run [--suite <name>] [--case <name>] [--tag <tag>] [--format console|json|markdown|speedscope] [--output <path>]
swift package benchmark check [--baseline <baseline.json>] [--statistic <name>] [--threshold <value>] [--budget <budget>] [--allow-debug]
swift package benchmark trace [same options as run] [--xctrace-output <path>] [--xctrace-template <name>]
swift package benchmark baseline write --input <report.json> --output <baseline.json>
swift package benchmark baseline update --input <report.json> --output <baseline.json>
swift package benchmark baseline check --input <report.json> --baseline <baseline.json>
swift package benchmark diff --input <report.json> --baseline <baseline.json> --format json
swift package benchmark render --input <report.json> --format console|json|markdown|speedscope
```

Unknown options are rejected.

`run`, `check` and `trace` ask the host for its plan, then measure each step in
a host process of its own. Steps cannot disturb each other through memory,
caches or runtime state, and each step records its peak memory. The plugin
also builds the interposer library and passes it with `--interposer`, so each
step is counted in a second process that loads it. With
`--xctrace-output`, one process measures every selected step so that xctrace
records a single trace. In per-step runs, whatever benchmarks print goes to
standard error, so standard output carries only the report.

SwiftPM runs command plugins in a sandbox. Commands that write a file with
`--output`, or write a baseline, need write access to that directory, granted
before `benchmark`:

```bash
swift package --allow-writing-to-directory .build benchmark run --format json --output .build/report.json
```

For performance baselines and CI gates, run the package workflow with SwiftPM's
release configuration. Put `--configuration release` before `benchmark`,
because it is a SwiftPM package option:

```bash
swift package --configuration release benchmark list
swift package --configuration release --allow-writing-to-directory .build benchmark run --format json --output .build/release-benchmark-report.json
swift package --configuration release benchmark check --baseline Benchmarks/baseline.json
```

The plugin compiles the host with the toolchain SwiftPM runs, and records that
compiler's version in the report's run metadata. Hosts find the package's
resource bundles, link XCFramework binary targets, link the C++ standard
library when a C++ target is involved, and import C and Objective-C modules
found through module maps, including with an external `--scratch-path`. The
package workflow runs on macOS and Linux; on Linux, Objective-C targets and
XCFramework binary targets are not available.

Advanced host-backed CLI usage is available through the executable:

```bash
swift run swift-benchmark-cli run \
  --host .build/release/ParserBenchmarkHost \
  --swift-version "$(swiftc --version 2>&1 | head -1)" \
  --case "Parse document" \
  --format json
```

`--swift-version` records the compiler that built the host; without it, run
metadata names the Swift release only. To count heap allocations with your own
host, build the interposer and pass it:

```bash
swift build -c release --product _BenchmarkInterposer
swift run swift-benchmark-cli run \
  --host .build/release/ParserBenchmarkHost \
  --interposer .build/release/lib_BenchmarkInterposer.dylib \
  --format json
```

On Linux the library is `lib_BenchmarkInterposer.so`, and the host needs
`-Xlinker --export-dynamic` for allocation sites to name its own functions; the
plugin links its hosts that way.

`swift-benchmark-cli --version`, `swift run BenchmarkCLI --version`, and the
plugin version command report the same repository release version.

The package plugin delegates execution to `BenchmarkCLI` after discovery and
host generation. `BenchmarkPlugin` is orchestration; `BenchmarkDiscoveryTool`
and `_BenchmarkDiscoveryCore` own package discovery and generated bridge/host
sources.

## Timeline And Traces

Timeline attribution captures the Benchmark/Instruments execution path:

```bash
swift package --allow-writing-to-directory .build benchmark run \
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
summaries. Each attribution's scope names its sample, so the spans of one
argument row or Dimension size stay with that row's samples. This does not
read OSLog or Console output. Report JSON is the
structured drill-down truth; Signpost/xctrace remains the Apple platform asset
for deeper Instruments analysis. `trace` captures the timeline without
`--timeline`.

Attach an existing Instruments trace to every case, optionally describing how
it was recorded:

```bash
swift package --allow-writing-to-directory .build benchmark run \
  --tag parser \
  --trace .build/parser.trace \
  --trace-tool xctrace \
  --trace-template "Time Profiler" \
  --format json \
  --output .build/report-with-trace.json
```

`--required-trace <path>` fails the run when the trace does not exist.
`--trace-command <command>` records the command that produced it.

Record a trace through `xcrun xctrace`:

```bash
swift package --allow-writing-to-directory .build benchmark trace \
  --tag parser \
  --xctrace-output .build/parser.trace \
  --xctrace-template "Time Profiler" \
  --format json \
  --output .build/report-with-xctrace.json
```

The report stores trace attachment provenance and command metadata. It does
not parse private `.trace` internals as a stable API.

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

The macros expand to the recorder API, which works without them:
`Instruments.current.span(_:attributes:_:)` and
`Instruments.current.event(_:attributes:)`. See
[Instruments Without swift-syntax](#instruments-without-swift-syntax).

## Swift Testing Bridge Boundaries

Supported:

- `@Suite(.benchmark...)` enrolls the supported tests in that suite and in
  suites nested inside it.
- `@Test(.benchmark...)` enrolls a single test or refines suite defaults.
- `.benchmark(configuration:)` sets the configuration; its argument must be an
  expression the generated bridge can evaluate, because the plugin reads it
  from source.
- Tests declared in an extension of an enrolled suite belong to that suite.
- `@Test(arguments:)` and `@Benchmark(arguments:)` produce benchmark rows when
  the declaration is benchmark-enrolled.
- Swift Testing tags flow into benchmark plan filtering and report metadata.
- Supported bridge cases run through `BenchmarkRunner`, not the Swift Testing
  runner.

Diagnosed boundaries:

- `private` and `fileprivate` benchmark-marked tests, and tests in private
  types, are not supported in the generated bridge. Use `internal`, or use
  native `@BenchmarkSuite` / `@Benchmark` in the same source scope.
- Benchmark-marked tests in an extension of a type declared in another target
  are diagnosed.
- Instance tests in enum or actor suites are diagnosed; make them `static`.
- Unsupported argument shapes fail with explicit diagnostics.
- Unsupported declarations fail with explicit diagnostics rather than being
  silently skipped.
- Ordinary `@Test` declarations without `.benchmark` are ignored by the
  benchmark command.

`BenchmarkTestingAdapter` measures suites in the current process and projects
`ReportDocument` verdicts into Swift Testing issues:

```swift
@Test func parserStaysWithinBudget() async throws {
  let adapter = BenchmarkTestingAdapter()
  let document = try await adapter.report(
    suites: [parserSuite],
    metadata: .local(id: "run:parser"),
    comparison: ComparisonPolicy(budgets: [
      BudgetPolicy(metric: .wallClock, statistic: .p95, limit: 5_000_000)
    ])
  )
  adapter.recordIssues(for: document)
}
```

The adapter is a sink; Benchmark core remains independent from the Testing
runtime. In-process runs share the test process with other tests, so they
leave out peak memory and their allocation counts include other tests' work.

## XCTest And Advanced Hosts

`BenchmarkXCTestAdapter` is for existing XCTest workflows. It measures suites
like `BenchmarkTestingAdapter`, attaches structured report JSON, and projects
verdict causes through XCTest failures and attachments. XCTest remains an
adapter sink; Benchmark and Report remain the truth.

Manual hosts are advanced flows for declarations only an executable target can
reach:

```swift
import Report

@main
struct ParserBenchmarkHost {
  static func main() async {
    await BenchmarkHost.run(discoveries: [ParserBenchmarks.self])
  }
}
```

```bash
swift run swift-benchmark-cli run \
  --host .build/debug/ParserBenchmarkHost \
  --case "Parse document" \
  --format json
```

The CLI drives the host through its own protocol; run the host through the CLI
rather than directly. Ordinary package workflows do not need this host for
library-target `@BenchmarkSuite` declarations or supported test-target
BenchmarkTesting declarations.

## Best Practices

- Prefer Tests-first authoring for application and library teams.
- Measure and check release builds; keep debug runs for local exploration.
- Keep benchmark bodies deterministic and explicit about setup.
- Use `blackHole` for values that would otherwise be optimized away.
- Use tags to separate fast local benchmarks from slower CI or release gates.
- Keep automatic batching unless a workload must run once per sample.
- Use fixed iterations by default; opt into adaptive or duration policies only
  when the workload needs it, and keep at least five samples for comparisons.
- Pick the metric and statistic that define a regression for your workload,
  such as p95 wall-clock time or median Swift allocations.
- Use `arguments` for input rows; integer arguments produce `Benchmark.Scale`
  curves.
- Store baselines under a reviewed path such as `Benchmarks/*.json`, recorded
  on the machine that runs the check.
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
- If generated host compilation fails with a missing C module, confirm the
  dependency is resolved through SwiftPM checkouts and rerun with a clean
  scratch path.
- If `check` refuses a debug build, add `--configuration release` before
  `benchmark`, or pass `--allow-debug` to judge the debug build anyway.
- If a baseline fails to load after upgrading, record it again with
  `baseline write`.
- If a report warns about noise, raise the iteration count, lengthen the
  batching target, or loosen that metric's threshold. If it warns about
  outliers, close other work on the machine and run again.
- If `instructions` and `cycles` are missing, the machine does not expose
  hardware counters to the process: virtual machines often do not, and on
  Linux the kernel must allow unprivileged counting
  (`kernel.perf_event_paranoid` of 2 or less) and a container must allow the
  `perf_event_open` system call.
- If the heap metrics are missing, the step was not measured by a counting
  process: run it through `swift package benchmark`, or pass `--interposer`
  with your own host.
- If allocation sites show image offsets instead of function names, the host
  was stripped of its symbols.
- If a report renderer is not enough, consume `ReportDocument` JSON and build a
  separate renderer/template outside the core Swift library.
