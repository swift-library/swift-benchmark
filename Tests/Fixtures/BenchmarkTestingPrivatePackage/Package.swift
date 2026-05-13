// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "BenchmarkTestingPrivatePackage",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../../..")
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
