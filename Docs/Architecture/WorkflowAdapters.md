# Workflow Adapters

## Scope / Purpose

This document owns user/tool workflow entry points over Benchmark and Report:
SwiftPM command workflow, CLI behavior, Swift Testing adapters, and XCTest
adapters.

Adapters consume the same model:

```text
BenchmarkDiscovery
  -> BenchmarkRunner.Plan
  -> Benchmark.Event.Stream
  -> ReportDocument
```

They do not replace the Benchmark runner and do not create a second report
truth.

## Current Implementation Status

Current source implements both host-backed and no-`--host` package workflows.
`BenchmarkCLI` forwards list/run/check/trace to `BenchmarkHost`, and the
SwiftPM `BenchmarkPlugin` discovers production `@BenchmarkSuite` declarations
in library targets plus supported test-target `@Suite(.benchmark...)` /
`@Test(.benchmark...)` declarations through the BenchmarkTesting bridge. The
plugin builds the package, generates an internal host, and delegates to the
same CLI semantics. Baseline write/update, diff, render, tag filters,
warmup/iteration/adaptive overrides, diagnostics, trace attachments,
`xctrace record` provenance, quiet output, and CI exit codes are wired through
the shared Report model. Explicit `--host` remains an advanced/debug override.

## SwiftPM Package Workflow

Implemented production benchmark workflow:

- `swift package benchmark list`,
- `swift package benchmark run`,
- `swift package benchmark check`,
- `swift package benchmark baseline write/update`,
- `swift package benchmark diff`,
- `swift package benchmark trace`.

This is the primary production benchmark entry point. It preserves Benchmark
semantics that a plain Swift Testing `@Test` body does not provide by itself:
warmup, measured iterations, adaptive/min/max-duration policies, samples,
Dimension rows, `ReportDocument`, baseline/budget verdicts, CI exit codes,
Memory/allocation evidence, timeline attribution, and xctrace artifacts.

Package workflow rules:

- discover code declarations through `_BenchmarkDiscovery` /
  `BenchmarkDiscovery`,
- bridge supported test-target `@Suite(.benchmark...)` /
  `@Test(.benchmark...)` declarations into generated `_BenchmarkDiscovery`
  records,
- build `BenchmarkRunner.Plan` before execution,
- consume `ReportDocument` for baseline/check/diff,
- keep code declarations as truth,
- do not require manifest/config files for discovery,
- do not require public provider boilerplate,
- do not rely on target naming conventions.

## CLI / Plugin

The SwiftPM plugin delegates behavior to the CLI. CLI and plugin must share:

- filters,
- warmup/iteration overrides,
- runner policy flags,
- Dimension flags where applicable,
- baseline/budget flags,
- diagnostics flags,
- trace flags,
- output paths,
- quiet/progress separation,
- documented exit codes.

Exit codes distinguish:

- success,
- invalid configuration,
- execution failure,
- regression failure,
- required diagnostic unavailable.

Success, no regression, and improvement all use exit code `0`.

## Swift Testing Adapter

Swift Testing adapters provide native UX:

```swift
@Suite(.benchmark(.iterations(100), .baseline("baseline.json")))
struct ParserPerformanceTests {
  @Test(.benchmark(.time(max: .milliseconds(30))))
  func parseSmallDocument() throws {
    try parser.parse(input)
  }
}
```

Adapter rules:

- `@Suite(.benchmark...)` provides suite-level benchmark traits.
- `@Test(.benchmark...)` provides case-level benchmark traits.
- Suite traits merge into contained tests.
- Test traits override, refine, or add to suite defaults.
- Execution still goes through `BenchmarkRunner.Plan` / `BenchmarkRunner`;
  Swift Testing lifecycle is an adapter sink, not the benchmark runner.
- In package workflow, supported test-target declarations are discovered by a
  generated BenchmarkTesting bridge. `private`/`fileprivate` tests and
  `@Test(arguments:)` are diagnosed instead of silently skipped.
- A plain Swift Testing `@Test` body must not be treated as a complete
  benchmark run, because it would lose warmup, multi-iteration samples,
  Dimension rows, Report comparison, and diagnostics semantics.
- Verdicts project to Swift Testing `Issue.record`.
- Attachments project to Swift Testing attachment sinks where available.
- `ReportDocument` remains the truth.

## XCTest Adapter

XCTest support remains useful for projects, CI systems, and Apple tooling that
still consume XCTest artifacts.

Adapter rules:

- run Benchmark/Report as a consumer,
- attach structured JSON reports/artifacts,
- fail with suite/case/verdict context,
- preserve source location where possible,
- do not replace Benchmark runner behavior.

## Acceptance Evidence

- Fixture package tests for list/run/check/baseline/update/diff/trace.
- CLI/plugin behavior parity tests.
- Filter and output-path tests.
- Exit-code tests.
- Swift Testing suite/test trait fixtures.
- Swift Testing issue/source-location tests.
- XCTest artifact/failure tests.
