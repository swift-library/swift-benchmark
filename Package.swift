// swift-tools-version: 6.3
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
    .library(name: "BenchmarkTesting", targets: ["BenchmarkTesting"]),
    .library(name: "BenchmarkXCTest", targets: ["BenchmarkXCTest"]),
    .executable(name: "swift-benchmark-cli", targets: ["BenchmarkCLI"]),
    .executable(name: "BenchmarkCLI", targets: ["BenchmarkCLI"]),
    .plugin(name: "BenchmarkPlugin", targets: ["BenchmarkPlugin"]),
  ],
  traits: [
    .trait(
      name: "Macros",
      description:
        "Declares the Instruments macros, which build swift-syntax. Without it, Instruments offers only its runtime API."
    ),
    .default(enabledTraits: ["Macros"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
  ],
  targets: [
    .target(
      name: "Instruments",
      dependencies: [.target(name: "InstrumentsMacro", condition: .when(traits: ["Macros"]))],
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
      dependencies: ["BenchmarkMacro", "_BenchmarkCounters"],
      path: "Sources/Benchmark"
    ),
    .target(
      name: "_BenchmarkCounters",
      path: "Sources/_BenchmarkCounters"
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
      dependencies: [
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      path: "Sources/_BenchmarkDiscoveryCore"
    ),
    .executableTarget(
      name: "BenchmarkDiscoveryTool",
      dependencies: ["_BenchmarkDiscoveryCore"],
      path: "Sources/BenchmarkDiscoveryTool"
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
      name: "AdapterTests",
      dependencies: ["Benchmark", "BenchmarkTesting", "BenchmarkXCTest", "Report"],
      path: "Tests/AdapterTests"
    ),
    .testTarget(
      name: "WorkflowTests",
      dependencies: ["Benchmark", "Report"],
      path: "Tests/WorkflowTests"
    ),
    .testTarget(
      name: "BenchmarkDiscoveryCoreTests",
      dependencies: ["_BenchmarkDiscoveryCore"],
      path: "Tests/BenchmarkDiscoveryCoreTests"
    ),
  ]
)
