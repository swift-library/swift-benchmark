# Changelog

## Unreleased

- **Breaking**: Requires Swift 6.3 or later. Deployment minimums are iOS 18
  and macOS 15 for all library and command-line products. Swift 6.0 through
  6.2 remain on 0.1.x.
- **Breaking**: Benchmarks measure several metrics. Timed samples record
  wall-clock and CPU time and values a workload records with
  `Benchmark.record(_:for:)`; a separate counting pass records Swift heap
  allocations, allocated bytes, retains and releases where the Swift runtime
  exposes its instrumentation hooks; and a step measured in a process of its
  own records its peak memory.
  `Sample`, measurement rows, statistics, baselines, budgets, verdict causes
  and Dimension curves are keyed by metric, and Report JSON no longer carries
  `schemaVersion`. Reports and baselines written by 0.1.x cannot be read:
  decoding a report fails with an error that says to generate it again, and
  the CLI says to record a baseline again.
- Short workloads are timed in batches: automatic batching grows each
  sample's call count until it lasts the target duration and reports per-call
  values. `BatchingPolicy` configures it and `--batch-size` fixes it.
- `swift package benchmark run`, `check` and `trace` measure each step in a
  host process of its own, which isolates steps from each other and lets each
  record its peak memory. With `--xctrace-output`, one traced process measures
  every selected step.
- **Breaking**: Comparisons use the median by default instead of the mean, and
  compare each Dimension size or argument row with the same row of the
  baseline. The measured metric's direction decides which change regresses.
  CLI options are `--statistic`, `--threshold <n>%|<metric>=<amount>`,
  `--budget <metric>:<statistic>:<amount>` and
  `--case-budget <suite>:<case>:<metric>:<statistic>:<amount>`, replacing
  `--baseline-metric`, `--threshold-percent`, `--threshold-ns` and the
  nanosecond budget forms.
- **Breaking**: `check` refuses to judge a debug build unless given
  `--allow-debug`. Reports warn when a baseline came from different run
  conditions, when the run is a debug build, and when a comparison has too few
  samples or too much noise for its threshold.
- **Breaking**: The CLI rejects unknown options and no longer accepts the
  `sample` alias. `--optional-diagnostic` and `--required-diagnostic` are
  removed; exit status 30 reports a missing required trace or a failed
  recording. `--swift-version` records the compiler that built the host.
- **Breaking**: The `markdown` report format, the Memory product, the MetricKit
  placeholder types and diagnostic metrics (`DiagnosticMetric`,
  `MetricProvider`, `CaseReport.diagnostics`) are removed. Trace attachments
  remain.
- **Breaking**: Report's public API keeps the report model, comparison
  policies, baselines, `ReportRecorder`, `ReportBuilder`, timeline attribution
  and `BenchmarkHost.run(discoveries:arguments:metadata:)`. `BenchmarkHost.run`
  no longer throws; it exits with status 2 for an invalid request or
  configuration and 1 for any other failure. The benchmark command, report
  renderers and formats, the host protocol, xctrace recording and trace
  exporters are no longer public.
- **Breaking**: Step, row and report identifiers keep suite and case names as
  written, with punctuation percent-encoded, so names that differ only in case
  or punctuation stay distinct. An argument row is identified by its values'
  descriptions instead of its position, so reordering arguments keeps baseline
  rows matched.
- **Breaking**: `Benchmark.Event.Kind` drops the discovery, suite,
  diagnostic, attachment and run-ended kinds, which no run emitted.
- **Breaking**: The BenchmarkTesting `.benchmark` trait takes only a
  configuration. `BenchmarkTestingAdapter` and `BenchmarkXCTestAdapter` take
  the `BenchmarkRunner` to measure with.
- The `Macros` package trait, enabled by default, declares the Instruments
  macros. Depending on swift-benchmark with `traits: []` gives the Instruments
  runtime API without building swift-syntax for it, with Swift 6.4 or later.
- The command plugin discovers declarations with SwiftSyntax alone, including
  `@Test` attributes on the function's line and members of extensions, and
  compiles the host with SwiftPM's toolchain. Hosts find the package's
  resource bundles and link XCFramework binary targets and the C++ standard
  library. `SWIFT_BENCHMARK_DISCOVERY_BACKEND` and
  `SWIFT_BENCHMARK_SWIFTSYNTAX_TOOL_PATH` are removed.
- The plugin builds only the targets that declare benchmarks and their
  dependencies, except a release run of test-target benchmarks, which builds
  every test target.
- A release host is compiled with optimization, so generated testing bridges
  run optimized inside measured batches, and the plugin no longer loads module
  maps from inside XCFrameworks.
- Traced commands no longer hang when xctrace or the benchmarks print more
  than a pipe holds.
- Timeline attributions of argument rows belong to their own row's samples.
  The iteration span records the row in `TimelineCorrelationKeys.row`, and
  `BenchmarkExecutionContext.rowID` names it for observers; previously every
  row's iteration matched every other row's samples.
- A configuration the host rejects, and a baseline or report file that cannot
  be read, exit with the configuration status 2 instead of 3.
- BenchmarkXCTest builds with swift-corelibs-xctest; `attachments(for:)`
  needs Apple's XCTest.

## 0.1.2

- Commands with `--xctrace-output` launch the benchmark host once, under
  xctrace, and report that traced run. Previously the host ran a second time
  outside the trace and the printed results came from that untraced run. A
  traced `check` applies the baseline and budget gate to the traced run and
  exits with the regression-failure code.
- Report JSON encodes the percentage change against a zero baseline as `null`
  and decodes it as an infinite change. Previously rendering such a report as
  JSON failed.
- `XctraceRecorder.record` accepts `targetStandardOutputPath` to write the
  launched process's standard output to a file.
- The README and UsageManual pin `.upToNextMinor(from: "0.1.2")`.

## 0.1.1

- `swift package benchmark check` measures the selected benchmarks once and
  takes both the printed verdict and the exit status from that measurement.
  Previously a second, separate run chose the exit status, so a check could
  print a failed verdict and still exit 0.
- A failed baseline or budget check prints its report before exiting nonzero.
  `swift-benchmark-cli check` exits with its regression-failure code instead of
  reporting a benchmark host failure.

## 0.1.0

- Instruments spans, events, function/initializer macros and recorder context
  support runtime instrumentation with Apple Signpost and portable fallbacks.
  Overlapping intervals use independent Apple backend identifiers.
- Benchmark provides Swift Testing and native declarations, argument rows,
  discovery, warmup, fixed/adaptive measurement and structured event streams.
- Report provides JSON evidence, baselines, budgets, Dimension curves, timeline
  attribution, memory/allocation adapters and macOS xctrace orchestration.
  Darwin resident-memory evidence includes the measured process peak.
- The SwiftPM command plugin supports package discovery and generated hosts in
  Debug and Release configurations, with C modulemap dependency support.
- Both CLI products and the plugin expose the same `--version` value.
- Macro expansion assertions report failures through Swift Testing.
- The package uses Apache License 2.0 with the Swift Runtime Library Exception.

The supported system window is iOS 18/26/27 and macOS 15/26/27. Swift tools 6.0
is the declared compiler minimum. Executable-only benchmark declarations use
the advanced host override; private/fileprivate Testing bridge declarations
receive diagnostics. MetricKit integration is an optional future diagnostics
capability.
