# BenchmarkTesting Discovery Bridge

Status: Accepted

Date: 2026-05-13

## Context

`BenchmarkTesting` exposes Swift Testing trait UX through
`@Suite(.benchmark...)` and `@Test(.benchmark...)`. Those declarations must run
through `BenchmarkRunner`, not the Swift Testing runner, so Benchmark keeps
warmup, iterations, samples, Dimension rows, ReportDocument output, diagnostics,
and CI verdict semantics.

Swift Testing's own `@Test` macro emits records into `__swift5_tests`, but that
record/accessor path is owned by Swift Testing. The generated thunks and
`Test.all` bridge are not a stable external execution contract for Benchmark.

## Decision

- Do not reuse Swift Testing `__swift5_tests`, `Test.all`, or internal record
  ABI as the Benchmark execution bridge.
- Implement pure `@Suite(.benchmark...)` / `@Test(.benchmark...)` package
  support with source scanning and generated `_BenchmarkDiscovery` bridge code.
- Follow the official SwiftPM plugin tool pattern:
  `BenchmarkPlugin -> BenchmarkDiscoveryTool -> _BenchmarkDiscoveryCore`.
  `BenchmarkPlugin` is a thin orchestrator that passes SwiftPM target metadata
  to `BenchmarkDiscoveryTool`, reads the tool's discovery plan, builds the
  generated host, and delegates execution to `BenchmarkCLI`.
- Keep all package discovery and source generation in `_BenchmarkDiscoveryCore`.
  This includes native `@BenchmarkSuite` reference discovery and Testing bridge
  generation. `BenchmarkCLI` owns benchmark/report workflows only and does not
  expose hidden discovery commands.
- The plugin target itself does not depend on SwiftSyntax, SwiftParser,
  Benchmark, Report, or local library targets. A SwiftSyntax/SwiftParser
  scanner remains the preferred semantic direction if the source-built tool path
  validates under SwiftPM command-plugin execution. A 2026-05-14 hard-gate spike
  added `SwiftParser` / `SwiftSyntax` only to `_BenchmarkDiscoveryCore` and
  verified `swift build --product BenchmarkDiscoveryTool` succeeds, but the
  real command-plugin path failed with `no such module 'SwiftParser'` while
  running `swift package ... benchmark list --format json` against the fixture
  package. Until that SwiftPM/toolchain path is fixed or a different tool
  packaging strategy is chosen, the package workflow uses the self-contained
  scanner behind `_BenchmarkDiscoveryCore` so `swift package benchmark` remains
  production usable without requiring users to pass serial build flags.
- The generated bridge links the user's test target and invokes supported test
  methods through `BenchmarkRunner`.
- `private` and `fileprivate` tests are not supported by the pure Testing
  bridge because the generated bridge source is outside the original lexical
  scope. Users should make those tests internal or use `@BenchmarkSuite` /
  `@Benchmark` for same-scope discovery.
- `@Test(arguments:)` is not mapped to `Benchmark.Dimension`. Benchmark input
  scale remains an explicit Dimension concept.
- `Benchmark` core must not import or depend on the `Testing` runtime.

## Consequences

The common test-target shape, where tests are internal by default, works through
`swift package benchmark` without a user-maintained host. The full private
member path remains covered by native `@BenchmarkSuite` / `@Benchmark`, whose
macros generate discovery in the original declaration scope.

The bridge intentionally extracts only Benchmark-owned semantics from Testing
traits: benchmark configuration and tags. Parameterized Testing data remains
separate from `Benchmark.Dimension`, and unsupported declarations fail with
explicit diagnostics instead of being silently skipped.
