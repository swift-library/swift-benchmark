<div align="center">

<p align="center">
  <a href="https://github.com/swift-library/swift-benchmark"><img src="Documentation/Assets/Logo.svg" width="160" alt="swift-benchmark logo"></a>
</p>

<h1 align="center">swift-benchmark</h1>

<p align="center">
  Catch performance regressions beside your tests with JSON baselines and metric budgets.
</p>

<p align="center">
  <a href="https://github.com/swift-library/swift-benchmark/actions/workflows/ci.yml"><img src="https://github.com/swift-library/swift-benchmark/actions/workflows/ci.yml/badge.svg?branch=master" alt="CI"></a>
  <img src="https://img.shields.io/badge/Swift-6.0%2B-F05138?style=flat" alt="Swift 6.0+">
  <img src="https://img.shields.io/badge/platforms-iOS%2018%2B%20%7C%20macOS%2015%2B-lightgrey?style=flat" alt="Platforms: iOS 18+ | macOS 15+">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-Apache--2.0-blue?style=flat" alt="License: Apache-2.0 WITH Swift-exception"></a>
</p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#quick-look">Quick look</a> ·
  <a href="#install">Install</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#requirements">Requirements</a> ·
  <a href="#documentation">Documentation</a> ·
  <a href="#contributing">Contributing</a> ·
  <a href="#license">License</a>
</p>

</div>

## Overview

Choose the metric that defines a regression and compare runs with a saved baseline. A p95 budget can fail even when the mean passes, and the report records a typed verdict for CI; the [usage manual](Documentation/UsageManual.md) covers measurement policies, instrumentation, and platform limits.

## Quick look

```swift
import Benchmark
import BenchmarkTesting
import Testing

@Suite(.benchmark(configuration: .init(warmup: .iterations(2), iterations: .iterations(20))))
struct SortingBenchmarks {
  @Test(arguments: [1_000, 10_000])
  func sort(count: Int) {
    blackHole((0..<count).reversed().sorted())
  }
}
```

## Install

Add the package and the products you use to `Package.swift`:

```swift
dependencies: [
  .package(
    url: "https://github.com/swift-library/swift-benchmark.git",
    .upToNextMinor(from: "0.1.2")
  ),
],
targets: [
  .target(
    name: "YourLibrary",
    dependencies: [
      .product(name: "Instruments", package: "swift-benchmark"),
    ]
  ),
  .testTarget(
    name: "YourLibraryTests",
    dependencies: [
      "YourLibrary",
      .product(name: "Benchmark", package: "swift-benchmark"),
      .product(name: "BenchmarkTesting", package: "swift-benchmark"),
    ]
  ),
]
```

The package also provides the `swift package benchmark` command plugin. It is
available in any package that depends on swift-benchmark.

> [!NOTE]
> swift-benchmark is pre-1.0. Minor releases may include source-breaking
> changes, so depend on it with `.upToNextMinor(from:)`.

## Usage

Run `swift package benchmark list` to discover declarations, then `swift package --configuration release benchmark run` to measure them. Use `benchmark check` with a saved JSON baseline and the metric or budget that matters to your application.

The [usage manual](Documentation/UsageManual.md) covers native and Swift Testing declarations, products, command options, baselines, diagnostics, and Instruments integration.

## Requirements

- Swift 6.0 or later
- iOS 18 or later, macOS 15 or later

Each release supports the three most recent major versions of each declared
platform, currently iOS 18, 26, and 27, and macOS 15, 26, and 27. The
[release reference](Documentation/Reference/Release.md)
describes compatibility and maintenance. `swift-benchmark-cli --version` and
`swift package benchmark --version` print the installed version.

## Documentation

- [Module documentation](Sources/Instruments/Instruments.docc/Instruments.md):
  the public API reference and module overview.

- [Usage manual](Documentation/UsageManual.md): every API, command, CI workflow,
  diagnostic, and adapter, with troubleshooting.
- [Product domains](Documentation/Architecture/ProductDomains.md): how
  Instruments, Benchmark, Report, and the adapters fit together.
- [Architecture](Documentation/Architecture/README.md): design notes for each
  product.
- [Changelog](CHANGELOG.md)

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and run its local validation commands
before opening a pull request. Report vulnerabilities through the
private route in [SECURITY.md](SECURITY.md).

## License

swift-benchmark is available under the Apache License 2.0 with the Swift
Runtime Library Exception. See [LICENSE.txt](LICENSE.txt) and [NOTICE](NOTICE).
