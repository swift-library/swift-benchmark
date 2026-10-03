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
SwiftPM `BenchmarkPlugin` follows the official plugin-tool pattern:
`BenchmarkPlugin -> BenchmarkDiscoveryTool -> _BenchmarkDiscoveryCore`.
The plugin passes SwiftPM target metadata to the discovery tool; the tool emits
one discovery plan covering production `@BenchmarkSuite` declarations in
library targets plus supported test-target `@Suite(.benchmark...)` /
`@Test(.benchmark...)` bridge declarations. The default discovery backend is
the self-contained scanner in `_BenchmarkDiscoveryCore`, so default
`swift package benchmark` does not build or link a SwiftSyntax discovery tool.
An opt-in SwiftSyntax backend exists as implementation tooling through an
external `BenchmarkSyntaxDiscoveryTool -> _BenchmarkSyntaxDiscoveryCore` path.
It must be explicitly selected by environment and does not change the public
Benchmark/Report model. The plugin builds the package, compiles the generated
host from the selected discovery plan, and delegates to the same CLI semantics.
Baseline write/update, diff, render, tag filters,
warmup/iteration/adaptive overrides, diagnostics, trace attachments,
`xctrace record` provenance, quiet output, and CI exit codes are wired through
the shared Report model. Explicit `--host` remains an advanced/debug override.
Generated host compilation supplies Swift module search paths and C modulemap
include paths discovered from SwiftPM checkout roots. The active build/scratch
root takes precedence, and package `.build` checkout roots are fallback
behavior for default or older local layouts.
Generated host linkage includes only discovered benchmark targets and their
recursive dependencies. Consolidated object files in an Xcode products
directory are filtered by that graph; unrelated libraries from another package
target or an earlier build must not enter the benchmark host.
The plugin builds discovered package/test targets with the same SwiftPM
configuration as the plugin tool path, so `swift package --configuration
release benchmark ...` can discover and link release object files from a clean
`.build` without requiring a separate prebuild step.

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
argument/scale rows, `ReportDocument`, baseline/budget verdicts, CI exit codes,
Memory/allocation evidence, timeline attribution, and xctrace artifacts.

Package workflow rules:

- discover package code declarations through `BenchmarkDiscoveryTool` and a
  single internal discovery plan,
- keep the stable self-contained scanner as the default discovery backend,
- allow `SWIFT_BENCHMARK_DISCOVERY_BACKEND=swiftsyntax` to route to an external
  SwiftSyntax discovery tool specified by `SWIFT_BENCHMARK_SWIFTSYNTAX_TOOL_PATH`,
- reference native macro-generated `_BenchmarkDiscovery` records for
  production `@BenchmarkSuite` declarations,
- bridge supported test-target `@Suite(.benchmark...)`,
  `@Test(.benchmark...)`, `@Test(arguments:)`, and suite-local
  `@Benchmark(arguments:)` declarations into generated `_BenchmarkDiscovery`
  records,
- build `BenchmarkRunner.Plan` before execution,
- consume `ReportDocument` for baseline/check/diff,
- keep code declarations as truth,
- do not require manifest/config files for discovery,
- do not require public provider boilerplate,
- do not rely on target naming conventions.

## CLI / Plugin

The SwiftPM plugin delegates behavior to the CLI. The plugin must stay a thin
SwiftPM orchestration layer: it may collect target metadata, call executable
tools through `context.tool(named:)`, compile generated host sources, and
propagate tool exit status, but it must not parse benchmark declarations or
generate bridge sources itself. It must not depend on the SwiftSyntax discovery
tool because that would force default command-plugin execution to build the
SwiftSyntax backend before environment routing can run. CLI and plugin must
share:

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

Generated host compilation is a plugin implementation detail. When the plugin
invokes `swiftc` directly, it must provide only the search paths needed to
match the package build. C modulemap include paths come from SwiftPM checkout
roots and from the discovered benchmark target's recursive source-module
dependency roots, so edited/path dependencies keep working. The plugin must not
scan every generated `.build/**/include/module.modulemap`, because those
directories can contain SwiftPM-generated module maps for Swift targets and can
create duplicate module definitions.

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
