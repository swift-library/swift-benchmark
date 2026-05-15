# BenchmarkTesting Discovery Bridge

Status: Accepted

Date: 2026-05-13

## Context

`BenchmarkTesting` exposes Swift Testing trait UX through
`@Suite(.benchmark...)` and `@Test(.benchmark...)`. Those declarations must run
through `BenchmarkRunner`, not the Swift Testing runner, so Benchmark keeps
warmup, iterations, samples, argument/scale rows, ReportDocument output,
diagnostics, and CI verdict semantics.

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
  validates under SwiftPM command-plugin execution. The accepted topology is
  still the official SwiftPM tool pattern:
  `plugin -> executableTarget tool -> core target`.
- A 2026-05-14 hard-gate investigation found that the topology itself is valid:
  minimal packages using `plugin -> executableTarget tool -> core target`, with
  the tool or core importing `SwiftParser` / `SwiftSyntax`, build and run through
  `context.tool(named:)` when that is the only SwiftSyntax use path. The same is
  true when the provider package contains macro targets that are not also pulled
  into the client through a library product.
- The failing shape is narrower: the client package both depends on a
  macro-driven library product from the provider package and invokes a command
  plugin from that same provider, while the plugin's executable tool/core also
  imports `SwiftParser` / `SwiftSyntax`.

  ```text
  client package
    -> provider library product
         -> provider macro target -> swift-syntax
    -> provider command plugin
         -> executable tool -> core/tool -> SwiftParser / SwiftSyntax
  ```

  In that shape, SwiftPM's host-tool build description links
  `SwiftParser-tool.build/*.o` into the tool, but the tool/core module compile
  step does not list `Modules-tool/SwiftParser.swiftmodule` as an input before
  compiling the importing module. The observed fixture failure is therefore
  `no such module 'SwiftParser'` during module compilation, not a rejection of
  plugin executable tools or of the `plugin -> tool -> core` graph.
- Public upstream evidence matches this problem class, but does not prove the
  exact fixture failure is permanently unsolved:
  - SwiftPM has had macro/plugin boundary dependency bugs where dependency
    traversal needed to be pruned when crossing macro and plugin boundaries
    ([swift-package-manager#8436](https://github.com/swiftlang/swift-package-manager/issues/8436),
    fixed by
    [swift-package-manager#8472](https://github.com/swiftlang/swift-package-manager/pull/8472)
    and listed in
    [SwiftPM release notes](https://github.com/swiftlang/swift-package-manager/releases)).
  - Swift Forums reports the same family of issue when macros and plugin tools
    both touch SwiftSyntax prebuilts; maintainers describe it as two build
    environments being mixed
    ([Swift Forums: Swift-Syntax Prebuilts for Macros](https://forums.swift.org/t/preview-swift-syntax-prebuilts-for-macros/80202)).
  - SwiftSyntax prebuilt failures have documented workarounds such as
    `--disable-experimental-prebuilts`
    ([swift-package-manager#9193](https://github.com/swiftlang/swift-package-manager/issues/9193)).
- Local repros found real bypass paths, so this is not recorded as "impossible":
  - Minimal `plugin -> executableTarget tool -> core/tool -> SwiftSyntax`
    packages pass.
  - The failing dual SwiftSyntax graph passes in a minimized reproduction when
    command-plugin execution uses `--disable-experimental-prebuilts`.
  - Applying that flag to a temporary copy of this package moves execution past
    the `SwiftParser` import failure; the next failure is a separate generated
    bridge compile/link issue around Swift Testing modules, not the SwiftSyntax
    hard gate.
- The accepted production decision is still not to require users or CI to pass
  `--disable-experimental-prebuilts`, and not to ship a half-migrated
  SwiftSyntax scanner that only works under special flags. Until SwiftPM's
  default host-tool path handles this dual SwiftSyntax graph reliably, or the
  discovery tool is repackaged as a binary/prebuilt/separate toolchain artifact
  that avoids source-building SwiftSyntax in the client graph, the package
  workflow uses the self-contained scanner behind `_BenchmarkDiscoveryCore`.
- The accepted A/B implementation keeps the self-contained scanner as the
  default production backend and adds an opt-in SwiftSyntax backend that is
  target/tool isolated:

  ```text
  BenchmarkPlugin
    -> BenchmarkDiscoveryTool
        -> _BenchmarkDiscoveryCore

  opt-in only:
  BenchmarkDiscoveryTool
    -> external BenchmarkSyntaxDiscoveryTool
        -> _BenchmarkSyntaxDiscoveryCore
  ```

  `BenchmarkPlugin` does not depend on `BenchmarkSyntaxDiscoveryTool`; otherwise
  default `swift package benchmark` would still build the SwiftSyntax tool
  before environment routing can run. The SwiftSyntax backend is enabled only
  with `SWIFT_BENCHMARK_DISCOVERY_BACKEND=swiftsyntax` and an absolute
  `SWIFT_BENCHMARK_SWIFTSYNTAX_TOOL_PATH`. Callers must pass
  `--disable-experimental-prebuilts` at the `swift package` layer when building
  and invoking that backend.
- `BenchmarkDiscoveryTool` also supports `SWIFT_BENCHMARK_DISCOVERY_BACKEND=auto`
  for developer probing. In `auto`, a failing SwiftSyntax backend may fall back
  to the stable scanner with a warning. Explicit `swiftsyntax` mode fails
  loudly and never silently degrades.
- The generated host may need Swift Testing runtime link/import arguments. Two
  layouts are accepted: toolchain `usr/lib/swift/macosx/testing` and Xcode
  `MacOSX.platform/Developer/Library/Frameworks/Testing.framework`. Missing
  Swift Testing modules are therefore a host compile/link argument problem, not
  a reason to bind Benchmark core to the Swift Testing runtime.
- The generated bridge links the user's test target and invokes supported test
  methods through `BenchmarkRunner`.
- `private` and `fileprivate` tests are not supported by the pure Testing
  bridge because the generated bridge source is outside the original lexical
  scope. Users should make those tests internal or use `@BenchmarkSuite` /
  `@Benchmark` for same-scope discovery.
- `@Test(arguments:)` is mapped to Benchmark argument rows when the declaration
  is benchmark-enrolled. Numeric and integer-raw-value arguments infer
  `Benchmark.Scale`; non-numeric arguments produce rows without curves.
- `Benchmark` core must not import or depend on the `Testing` runtime.

## Consequences

The common test-target shape, where tests are internal by default, works through
`swift package benchmark` without a user-maintained host. The full private
member path remains covered by native `@BenchmarkSuite` / `@Benchmark`, whose
macros generate discovery in the original declaration scope.

The bridge intentionally extracts Benchmark-owned semantics from Testing:
benchmark configuration, tags, and parameterized argument rows. Unsupported
argument shapes fail with explicit diagnostics instead of being silently
skipped.
