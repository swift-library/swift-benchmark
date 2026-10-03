// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "swift-benchmark",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "Instruments", targets: ["Instruments"]),
    .library(name: "Benchmark", targets: ["Benchmark"]),
    .library(name: "Report", targets: ["Report"]),
    .library(name: "Memory", targets: ["Memory"]),
    .library(name: "BenchmarkTesting", targets: ["BenchmarkTesting"]),
    .library(name: "BenchmarkXCTest", targets: ["BenchmarkXCTest"]),
    .executable(name: "swift-benchmark-cli", targets: ["BenchmarkCLI"]),
    .executable(name: "BenchmarkCLI", targets: ["BenchmarkCLI"]),
    .plugin(name: "BenchmarkPlugin", targets: ["BenchmarkPlugin"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
  ],
  targets: [
    .target(
      name: "Instruments",
      dependencies: ["InstrumentsMacro"],
      path: "Sources/Instruments"
    ),
    .macro(
      name: "InstrumentsMacro",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      path: "Sources/InstrumentsMacro"
    ),
    .target(
      name: "Benchmark",
      dependencies: ["BenchmarkMacro"],
      path: "Sources/Benchmark"
    ),
    .macro(
      name: "BenchmarkMacro",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      path: "Sources/BenchmarkMacro"
    ),
    .target(
      name: "Report",
      dependencies: ["Benchmark", "Instruments"],
      path: "Sources/Report"
    ),
    .target(
      name: "Memory",
      dependencies: ["Report"],
      path: "Sources/Memory"
    ),
    .target(
      name: "BenchmarkTesting",
      dependencies: ["Benchmark", "Report"],
      path: "Sources/BenchmarkTesting"
    ),
    .target(
      name: "BenchmarkXCTest",
      dependencies: ["Benchmark", "Report"],
      path: "Sources/BenchmarkXCTest"
    ),
    .executableTarget(
      name: "BenchmarkCLI",
      dependencies: [
        "Benchmark",
        "Report",
      ],
      path: "Sources/BenchmarkCLI"
    ),
    .target(
      name: "_BenchmarkDiscoveryCore",
      path: "Sources/_BenchmarkDiscoveryCore"
    ),
    .target(
      name: "_BenchmarkSyntaxDiscoveryCore",
      dependencies: [
        "_BenchmarkDiscoveryCore",
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      path: "Sources/_BenchmarkSyntaxDiscoveryCore"
    ),
    .executableTarget(
      name: "BenchmarkDiscoveryTool",
      dependencies: ["_BenchmarkDiscoveryCore"],
      path: "Sources/BenchmarkDiscoveryTool"
    ),
    .executableTarget(
      name: "BenchmarkSyntaxDiscoveryTool",
      dependencies: ["_BenchmarkSyntaxDiscoveryCore"],
      path: "Sources/BenchmarkSyntaxDiscoveryTool"
    ),
    .plugin(
      name: "BenchmarkPlugin",
      capability: .command(
        intent: .custom(
          verb: "benchmark",
          description: "Render or run swift-benchmark reports"
        ),
        permissions: []
      ),
      dependencies: [
        "BenchmarkCLI",
        "BenchmarkDiscoveryTool",
      ],
      path: "Plugins/BenchmarkPlugin"
    ),
    .target(
      name: "MacroTesting",
      dependencies: [
        .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
      ],
      path: "Tests/MacroTesting"
    ),
    .testTarget(
      name: "InstrumentsTests",
      dependencies: [
        "Instruments",
        "InstrumentsMacro",
        "MacroTesting",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      path: "Tests/InstrumentsTests"
    ),
    .testTarget(
      name: "BenchmarkTests",
      dependencies: [
        "Benchmark",
        "BenchmarkMacro",
        "MacroTesting",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      path: "Tests/BenchmarkTests"
    ),
    .testTarget(
      name: "ReportTests",
      dependencies: ["Benchmark", "Instruments", "Report"],
      path: "Tests/ReportTests",
      resources: [.process("Fixtures")]
    ),
    .testTarget(
      name: "MemoryTests",
      dependencies: ["Memory", "Report"],
      path: "Tests/MemoryTests"
    ),
    .testTarget(
      name: "AdapterTests",
      dependencies: ["Benchmark", "BenchmarkTesting", "BenchmarkXCTest", "Report"],
      path: "Tests/AdapterTests"
    ),
    .testTarget(
      name: "WorkflowTests",
      path: "Tests/WorkflowTests"
    ),
    .testTarget(
      name: "BenchmarkDiscoveryCoreTests",
      dependencies: ["_BenchmarkDiscoveryCore"],
      path: "Tests/BenchmarkDiscoveryCoreTests"
    ),
    .testTarget(
      name: "BenchmarkSyntaxDiscoveryCoreTests",
      dependencies: ["_BenchmarkDiscoveryCore", "_BenchmarkSyntaxDiscoveryCore"],
      path: "Tests/BenchmarkSyntaxDiscoveryCoreTests"
    ),
  ]
)
