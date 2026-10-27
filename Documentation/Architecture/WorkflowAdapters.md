# Workflow Adapters

## Scope / Purpose

This document owns user/tool workflow entry points over Benchmark and Report:
the SwiftPM command workflow, CLI behavior, and the Swift Testing and XCTest
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

## SwiftPM Package Workflow

`swift package benchmark` is the primary benchmark entry point: `list`, `run`,
`check`, `trace`, `baseline write/update/check`, `diff` and `render`. It
preserves what a plain Swift Testing `@Test` body does not provide: warmup,
batching, measured iterations, adaptive policies, samples of every metric,
argument/scale rows, per-step process isolation, `ReportDocument`,
baseline/budget verdicts and warnings, CI exit codes, timeline attribution and
xctrace artifacts. It runs on macOS and Linux.

The plugin follows the official plugin-tool pattern:
`BenchmarkPlugin -> BenchmarkDiscoveryTool -> _BenchmarkDiscoveryCore`.

1. The plugin passes SwiftPM target metadata to the discovery tool.
2. The tool parses each target's Swift sources with SwiftSyntax and writes one
   discovery plan: native `@BenchmarkSuite` types in library targets, and a
   generated BenchmarkTesting bridge for enrolled test-target declarations,
   plus the host's `main.swift`.
3. The plugin builds the package in the configuration of its tool path, so
   `swift package --configuration release benchmark ...` links release object
   files without a separate prebuild.
4. The plugin compiles the host with the `swiftc` of the toolchain SwiftPM runs
   and runs the CLI with the host and that compiler's version.

Package workflow rules:

- code declarations are the truth: no manifest or config files, provider
  boilerplate or target naming conventions,
- native `@BenchmarkSuite` declarations are referenced through their
  macro-generated `_BenchmarkDiscovery` types,
- supported test-target `@Suite(.benchmark...)`, `@Test(.benchmark...)`,
  `@Test(arguments:)` and suite-local `@Benchmark` declarations, including
  members of extensions of their types, are bridged into generated
  `_BenchmarkDiscovery` records; unsupported ones are diagnosed with their
  source location instead of being skipped,
- declarations only an executable target can reach use `--host`.

## Generated Host

The host is a plugin implementation detail:

- It lives in the plugin's work directory, the one place the command-plugin
  sandbox lets the plugin write; the module cache lives there too.
- The build's resource bundles are linked next to it, where `Bundle.module`
  looks for them.
- It links only the discovered targets and their recursive dependencies.
  Consolidated object files in a products directory are filtered by that graph.
- XCFramework binary targets contribute the macOS slice for the machine's
  architecture: headers on the include path and their library or framework.
  Targets with C++ or Objective-C++ sources add the C++ standard library.
- C and Objective-C module maps come from SwiftPM checkout roots, with the
  active scratch root first, and from the discovered targets' Clang dependency
  roots. The plugin does not scan every generated `module.modulemap`, because
  SwiftPM also generates them for Swift targets and duplicates would conflict.
- Testing bridge hosts link the toolchain's Swift Testing runtime, or the SDK
  platform's `Testing.framework`, and XCTest, which compiled test modules may
  reference; each test target's entry point is localized so the host's own
  `main` wins.

## CLI

The plugin delegates behavior to the CLI and stays thin: it collects target
metadata, runs tools through `context.tool(named:)`, compiles the generated
host and propagates exit status, but it does not parse declarations or generate
bridge sources itself.

The CLI drives a host through a package-internal protocol. `list` returns the
host's plan and run metadata. `run`, `check` and `trace` then run
`measure --step <id> --isolated` once per step, each in a host process of its
own. Given `--interposer`, which the plugin passes after building the
`_BenchmarkInterposer` product, each step runs twice instead: `--timing-only` in
a plain process, then `--counting-only --batch-size <timed size>` in a process
that loads the interposer, with `--allocation-sites` when requested; the CLI
inserts the counting samples into the timed row. With `--xctrace-output`, one
`measure` under xctrace measures every selected step. Hosts write their output
to a file the CLI names, and their standard output goes to the CLI's standard
error. The CLI concatenates the steps' event records, builds the report, applies
the baseline, budgets and warnings, attaches traces and renders. `check` refuses
a debug host before measuring unless given `--allow-debug`.

Options cover filters, warmup/iteration/batching overrides, adaptive policies,
comparison and budgets, the interposer and allocation sites, trace attachments
and xctrace recording, output paths, quiet output and the host compiler's
version. Unknown options are rejected.

Exit codes:

| Status | Meaning |
| --- | --- |
| `0` | Success, including improvements |
| `2` | Invalid configuration, such as an unknown option, an unreadable baseline or a refused debug build |
| `3` | A host failed |
| `20` | A regression or budget failure in `check`, `compare --fail-on-regression` or `baseline check` |
| `30` | A required trace is missing or recording one failed |

`check` measures the selected plan once; the printed report and the exit status
come from the same `ReportDocument`.

## Swift Testing Adapter

Swift Testing suites and tests enroll with the BenchmarkTesting trait:

```swift
@Suite(.benchmark(configuration: .init(warmup: .iterations(2), iterations: .iterations(20))))
struct ParserPerformanceTests {
  @Test func parseSmallDocument() throws {
    try blackHole(parser.parse(input))
  }
}
```

Adapter rules:

- `@Suite(.benchmark...)` enrolls contained and nested tests;
  `@Test(.benchmark...)` enrolls one test, and its configuration overrides the
  suite's.
- The package workflow reads the trait from source; `swift test` runs enrolled
  tests once, as tests.
- Execution goes through `BenchmarkRunner.Plan` / `BenchmarkRunner`; the Swift
  Testing lifecycle is an adapter sink, not the benchmark runner.
- `BenchmarkTestingAdapter` measures suites in process with a given runner and
  projects verdict causes to `Issue.record`.
- `ReportDocument` remains the truth.

## XCTest Adapter

XCTest support serves projects, CI systems and Apple tooling that consume
XCTest artifacts. `BenchmarkXCTestAdapter` measures suites in process like the
Swift Testing adapter, attaches the structured JSON report, fails with
suite/case/verdict context, and preserves source locations where possible. It
does not replace Benchmark runner behavior.

## Acceptance Checks

- Package workflow for list/run/check/baseline/diff/trace in debug and release
  (`PluginWorkflowTests`).
- Hosts for packages with resources, binary targets, and C, Objective-C and C++
  targets, without extra sandbox permission (`PluginWorkflowTests`).
- One host process per step, a timing and a counting process per step with
  the interposer, one traced process for xctrace, and the debug gate before
  measuring (`CLIWorkflowTests`).
- Discovery of native, bridged, same-line and extension declarations and their
  diagnostics (`DiscoveryPlannerTests`, `TestingBridgeTests`).
- Exit codes and report forwarding (`CLIWorkflowTests`, `PluginWorkflowTests`).
- Swift Testing and XCTest adapter verdicts and attachments (`AdapterTests`).
