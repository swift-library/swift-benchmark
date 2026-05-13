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
  support with SwiftSyntax source scanning and generated `_BenchmarkDiscovery`
  bridge code.
- Keep the scanner in a hidden `BenchmarkCLI` tool command consumed by
  `BenchmarkPlugin`. The plugin target itself does not depend on SwiftSyntax or
  SwiftParser, and `Benchmark` core does not depend on Testing or SwiftSyntax.
  A SwiftSyntax/SwiftParser scanner was validated as the preferred semantic
  direction, but SwiftPM command-plugin tool builds on Swift 6.3.1 fail under
  default parallelism with `no such module 'SwiftParser'`; the same path works
  with `--jobs 1`. Until that toolchain limitation is removed or the scanner is
  shipped as a prebuilt/otherwise stable tool, the package workflow uses the
  self-contained scanner so `swift package benchmark` remains production usable
  without requiring users to pass serial build flags.
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
