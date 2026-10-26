// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

// Fixture deadlines include cold dependency builds on hosted runners.
@Suite("Package Traits")
struct PackageTraitWorkflowTests {
  @Test(.timeLimit(.minutes(10)))
  func instrumentsBuildsWithoutSwiftSyntaxWhenMacrosAreDisabled() async throws {
    let package = URL(fileURLWithPath: scratchPath("fixture-instruments-runtime-package"))
    let scratch = URL(fileURLWithPath: scratchPath("fixture-instruments-runtime-scratch"))
    try? FileManager.default.removeItem(at: package)
    try? FileManager.default.removeItem(at: scratch)
    try writeFile(
      """
      // swift-tools-version: 6.3
      import PackageDescription

      let package = Package(
        name: "InstrumentsRuntime",
        platforms: [.macOS(.v15)],
        dependencies: [
          .package(
            name: "swift-benchmark", path: \(swiftStringLiteral(repositoryRoot().path)), traits: [])
        ],
        targets: [
          .executableTarget(
            name: "InstrumentsRuntime",
            dependencies: [.product(name: "Instruments", package: "swift-benchmark")]
          )
        ]
      )
      """,
      to: package.appendingPathComponent("Package.swift")
    )
    try writeFile(
      """
      import Instruments

      print(Instruments.current.span("work") { 21 * 2 })
      """,
      to: package.appendingPathComponent("Sources/InstrumentsRuntime/main.swift")
    )
    let swiftPackage = [
      "swift", "build", "--package-path", package.path, "--scratch-path", scratch.path,
    ]

    _ = try await runProcess(executable: "/usr/bin/env", arguments: swiftPackage)
    let binPath = try await runProcess(
      executable: "/usr/bin/env", arguments: swiftPackage + ["--show-bin-path"]
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    let run = try await runProcess(
      executable: URL(fileURLWithPath: binPath).appendingPathComponent("InstrumentsRuntime").path,
      arguments: [])
    let products = try FileManager.default.subpathsOfDirectory(atPath: binPath)

    #expect(run.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    #expect(products.contains { $0.hasPrefix("Instruments.") || $0.contains("/Instruments.") })
    // SwiftPM 6.3 still builds the macro target its trait condition excludes.
    #if compiler(>=6.4)
      #expect(!products.contains { $0.contains("SwiftSyntax") || $0.contains("InstrumentsMacro") })
    #endif
  }
}
