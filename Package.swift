// swift-tools-version: 6.0
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
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
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
      ],
      path: "Plugins/BenchmarkPlugin"
    ),
    .testTarget(
      name: "InstrumentsTests",
      dependencies: [
        "Instruments",
        "InstrumentsMacro",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ],
      path: "Tests/InstrumentsTests"
    ),
    .testTarget(
      name: "BenchmarkTests",
      dependencies: [
        "Benchmark",
        "BenchmarkMacro",
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
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
  ]
)
