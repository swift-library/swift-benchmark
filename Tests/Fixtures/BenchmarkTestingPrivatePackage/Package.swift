// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import PackageDescription

let package = Package(
  name: "BenchmarkTestingPrivatePackage",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(name: "swift-benchmark", path: "../../..")
  ],
  targets: [
    .testTarget(
      name: "PrivateBenchmarkTests",
      dependencies: [
        .product(name: "Benchmark", package: "swift-benchmark"),
        .product(name: "BenchmarkTesting", package: "swift-benchmark"),
      ]
    )
  ]
)
