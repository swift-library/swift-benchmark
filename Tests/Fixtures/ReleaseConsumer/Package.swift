// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2026 Xudong Xu

import PackageDescription

let package = Package(
  name: "ReleaseConsumer",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [.library(name: "ReleaseConsumer", targets: ["ReleaseConsumer"])],
  dependencies: [
    .package(
      url: "https://github.com/swift-library/swift-benchmark.git", revision: "release-candidate")
  ],
  targets: [
    .target(
      name: "ReleaseConsumer",
      dependencies: [
        .product(name: "Benchmark", package: "swift-benchmark"),
        .product(name: "Instruments", package: "swift-benchmark"),
      ]
    ),
    .testTarget(
      name: "ReleaseConsumerTests",
      dependencies: [
        "ReleaseConsumer",
        .product(name: "Benchmark", package: "swift-benchmark"),
        .product(name: "Instruments", package: "swift-benchmark"),
        .product(name: "Report", package: "swift-benchmark"),
        .product(name: "Memory", package: "swift-benchmark"),
        .product(name: "BenchmarkTesting", package: "swift-benchmark"),
        .product(name: "BenchmarkXCTest", package: "swift-benchmark"),
      ]
    ),
  ]
)
