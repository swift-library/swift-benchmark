// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import PackageDescription

let package = Package(
  name: "BenchmarkPackageFixture",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "FixtureBenchmarkLibrary", targets: ["FixtureBenchmarkLibrary"]),
    .executable(name: "FixtureBenchmarks", targets: ["FixtureBenchmarks"]),
  ],
  dependencies: [
    .package(name: "swift-benchmark", path: "../../..")
  ],
  targets: [
    .executableTarget(
      name: "FixtureBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "swift-benchmark"),
        .product(name: "Report", package: "swift-benchmark"),
      ]
    ),
    .target(
      name: "FixtureBenchmarkLibrary",
      dependencies: [
        .product(name: "Benchmark", package: "swift-benchmark")
      ]
    ),
    .testTarget(
      name: "FixtureBenchmarkTests",
      dependencies: [
        "FixtureBenchmarkLibrary",
        .product(name: "Benchmark", package: "swift-benchmark"),
        .product(name: "BenchmarkTesting", package: "swift-benchmark"),
        .product(name: "BenchmarkXCTest", package: "swift-benchmark"),
      ]
    ),
  ]
)
