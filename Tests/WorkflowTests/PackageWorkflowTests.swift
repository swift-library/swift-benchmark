// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Testing

@Suite("Package Workflow")
struct PackageWorkflowTests {
  @Test(.timeLimit(.minutes(3)))
  func cliProductsReportTheSameVersion() throws {
    let version = try runProcess(executable: cliPath(), arguments: ["--version"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let aliasVersion = try runProcess(
      executable: URL(fileURLWithPath: try cliPath()).deletingLastPathComponent()
        .appendingPathComponent("BenchmarkCLI").path,
      arguments: ["--version"]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(version.hasPrefix("swift-benchmark-cli "))
    #expect(version == aliasVersion)
  }

  @Test(.timeLimit(.minutes(2)))
  func fixturePackageHostWorksThroughCLI() throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package")
    try? FileManager.default.removeItem(atPath: scratchPath)

    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "build",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--product",
        "FixtureBenchmarks",
      ]
    )
    let binPath = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "build",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--product",
        "FixtureBenchmarks",
        "--show-bin-path",
      ]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let hostPath = URL(fileURLWithPath: binPath)
      .appendingPathComponent("FixtureBenchmarks")
      .path

    let cli = try cliPath()
    let list = try runProcess(
      executable: cli,
      arguments: [
        "list",
        "--host",
        hostPath,
        "--format",
        "json",
      ]
    )
    let run = try runProcess(
      executable: cli,
      arguments: [
        "run",
        "--host",
        hostPath,
        "--format",
        "json",
        "--case",
        "Noop",
      ]
    )

    #expect(list.contains("\"suite\" : \"Fixture\""))
    #expect(list.contains("\"caseName\" : \"Noop\""))
    #expect(run.contains("\"schemaVersion\" : 2"))
    #expect(run.contains("\"name\" : \"Noop\""))
    #expect(run.contains("\"measurement\""))
  }

  @Test(.timeLimit(.minutes(3)))
  func fixturePackageCommandGeneratesHostWithoutUserBoilerplate() throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package-plugin")
    try? FileManager.default.removeItem(atPath: scratchPath)
    try FileManager.default.createDirectory(
      atPath: scratchPath,
      withIntermediateDirectories: true
    )
    let reportPath = URL(fileURLWithPath: scratchPath).appendingPathComponent("report.json").path
    let baselinePath = URL(fileURLWithPath: scratchPath).appendingPathComponent("baseline.json")
      .path
    let tracePath = URL(fileURLWithPath: scratchPath).appendingPathComponent("run.trace").path
    let testingReportPath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("testing-report.json")
      .path
    let testingBaselinePath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("testing-baseline.json")
      .path
    let testingTracePath = URL(fileURLWithPath: scratchPath)
      .appendingPathComponent("testing.trace")
      .path
    let fakeXcrunPath = URL(fileURLWithPath: scratchPath).appendingPathComponent("fake-xcrun").path
    try writeFakeXcrun(to: fakeXcrunPath)

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "fast",
        "--format",
        "json",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "testingBridge",
        "--format",
        "json",
        "--output",
        testingReportPath,
        "--quiet",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "baseline",
        "write",
        "--input",
        testingReportPath,
        "--output",
        testingBaselinePath,
        "--quiet",
      ]
    )
    let testingCheck = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "check",
        "--tag",
        "testingBridge",
        "--baseline",
        testingBaselinePath,
        "--threshold-percent",
        "1000000",
        "--format",
        "json",
      ]
    )
    let testingDiff = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "diff",
        "--input",
        testingReportPath,
        "--baseline",
        testingBaselinePath,
        "--format",
        "json",
      ]
    )
    let testingTrace = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "trace",
        "--tag",
        "testingBridge",
        "--format",
        "json",
        "--xctrace-output",
        testingTracePath,
        "--xcrun",
        fakeXcrunPath,
      ]
    )
    let allList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--format",
        "json",
      ]
    )
    let testingList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "testingBridge",
        "--format",
        "json",
      ]
    )
    let standaloneList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "standalone",
        "--format",
        "json",
      ]
    )
    let run = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "library",
        "--format",
        "json",
      ]
    )
    let testingRun = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "testingBridge",
        "--format",
        "json",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "library",
        "--format",
        "json",
        "--output",
        reportPath,
        "--quiet",
      ]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "baseline",
        "write",
        "--input",
        reportPath,
        "--output",
        baselinePath,
        "--quiet",
      ]
    )
    let check = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "check",
        "--tag",
        "library",
        "--baseline",
        baselinePath,
        "--threshold-percent",
        "1000000",
        "--format",
        "json",
      ]
    )
    let diff = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "diff",
        "--input",
        reportPath,
        "--baseline",
        baselinePath,
        "--format",
        "json",
      ]
    )
    let trace = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "trace",
        "--tag",
        "library",
        "--format",
        "json",
        "--xctrace-output",
        tracePath,
        "--xcrun",
        fakeXcrunPath,
      ]
    )

    #expect(list.contains("\"suite\" : \"LibraryFixture\""))
    #expect(list.contains("\"tags\""))
    #expect(allList.contains("\"suite\" : \"LibraryFixture\""))
    #expect(allList.contains("\"suite\" : \"TestingFixture\""))
    #expect(allList.contains("\"suite\" : \"StandaloneTestingBenchmarks\""))
    #expect(testingList.contains("\"caseName\" : \"Suite Noop\""))
    #expect(testingList.contains("\"caseName\" : \"Case Override\""))
    #expect(testingList.contains("\"testingBridge\""))
    #expect(!testingList.contains("Plain Test"))
    #expect(standaloneList.contains("\"caseName\" : \"Standalone Testing Benchmark\""))
    #expect(standaloneList.contains("\"standalone\""))
    #expect(run.contains("\"schemaVersion\" : 2"))
    #expect(run.contains("\"name\" : \"Noop\""))
    #expect(run.contains("\"tags\""))
    #expect(testingRun.contains("\"schemaVersion\" : 2"))
    #expect(testingRun.contains("\"name\" : \"Suite Noop\""))
    #expect(testingRun.contains("\"name\" : \"Case Override\""))
    #expect(testingRun.contains("\"TestingFixture\""))
    #expect(testingRun.contains("\"iterations\" : \"iterations(1)\""))
    #expect(testingRun.contains("\"iterations\" : \"iterations(2)\""))
    #expect(FileManager.default.fileExists(atPath: reportPath))
    #expect(FileManager.default.fileExists(atPath: baselinePath))
    #expect(FileManager.default.fileExists(atPath: testingReportPath))
    #expect(FileManager.default.fileExists(atPath: testingBaselinePath))
    #expect(check.contains("\"baseline\""))
    #expect(diff.contains("\"baseline\""))
    #expect(testingCheck.contains("\"baseline\""))
    #expect(testingDiff.contains("\"baseline\""))
    #expect(trace.contains("\"attributions\""))
    #expect(trace.contains("\"Instruments trace\""))
    #expect(trace.contains("\"xctrace\""))
    #expect(testingTrace.contains("\"attributions\""))
    #expect(testingTrace.contains("\"Instruments trace\""))
    #expect(testingTrace.contains("\"xctrace\""))
    #expect(FileManager.default.fileExists(atPath: tracePath))
    #expect(FileManager.default.fileExists(atPath: testingTracePath))
    let pluginVersion = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift", "package", "--package-path", fixturePath, "--scratch-path", scratchPath,
        "benchmark", "--version",
      ]
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let cliVersion = try runProcess(executable: cliPath(), arguments: ["--version"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(pluginVersion == cliVersion)

  }

  @Test(.timeLimit(.minutes(4)))
  func fixturePackageCommandGeneratesReleaseHostWithoutPrebuild() throws {
    let fixturePath = fixturePackagePath()
    let scratchPath = scratchPath("fixture-benchmark-package-plugin-release")
    try? FileManager.default.removeItem(atPath: scratchPath)
    try FileManager.default.createDirectory(
      atPath: scratchPath,
      withIntermediateDirectories: true
    )

    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--configuration",
        "debug",
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "fast",
        "--format",
        "json",
      ]
    )

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--configuration",
        "release",
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "list",
        "--tag",
        "fast",
        "--format",
        "json",
      ]
    )
    let run = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        fixturePath,
        "--scratch-path",
        scratchPath,
        "--configuration",
        "release",
        "--allow-writing-to-directory",
        scratchPath,
        "benchmark",
        "run",
        "--tag",
        "fast",
        "--warmup",
        "0",
        "--iterations",
        "1",
        "--format",
        "json",
      ]
    )

    #expect(list.contains("\"suite\" : \"LibraryFixture\""))
    #expect(list.contains("\"caseName\" : \"Noop\""))
    #expect(run.contains("\"buildConfiguration\" : \"release\""))
  }

  @Test(.timeLimit(.minutes(3)))
  func fixturePackageCommandFindsCModuleMapsInExternalScratchPath() throws {
    let sourceRoot = URL(fileURLWithPath: scratchPath("fixture-c-module-package-source"))
    let scratch = URL(fileURLWithPath: scratchPath("fixture-c-module-package-external-scratch"))
    try? FileManager.default.removeItem(at: sourceRoot)
    try? FileManager.default.removeItem(at: scratch)
    try FileManager.default.createDirectory(
      at: sourceRoot,
      withIntermediateDirectories: true
    )

    let dependency = sourceRoot.appendingPathComponent("CModuleDependency")
    let package = sourceRoot.appendingPathComponent("CModuleBenchmarkPackage")
    try writeCModuleDependencyPackage(at: dependency)
    try initializeGitRepository(at: dependency)
    try writeCModuleBenchmarkPackage(
      at: package,
      dependency: dependency,
      swiftBenchmarkRoot: repositoryRoot()
    )
    try FileManager.default.createDirectory(
      at: scratch,
      withIntermediateDirectories: true
    )

    let list = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        package.path,
        "--scratch-path",
        scratch.path,
        "--allow-writing-to-directory",
        scratch.path,
        "benchmark",
        "list",
        "--tag",
        "cModule",
        "--format",
        "json",
      ]
    )

    #expect(list.contains("\"suite\" : \"CModuleFixture\""))
    #expect(list.contains("\"caseName\" : \"CModuleNoop\""))
  }

  @Test(.timeLimit(.minutes(2)))
  func fixturePackageCommandReportsTestingBridgeDiagnostics() throws {
    let privatePackage = fixturePath("BenchmarkTestingPrivatePackage")
    let privateScratch = scratchPath("fixture-benchmark-testing-private")
    try? FileManager.default.removeItem(atPath: privateScratch)
    try FileManager.default.createDirectory(
      atPath: privateScratch,
      withIntermediateDirectories: true
    )
    let privateFailure = try runProcessFailure(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        privatePackage,
        "--scratch-path",
        privateScratch,
        "--allow-writing-to-directory",
        privateScratch,
        "benchmark",
        "list",
        "--format",
        "json",
      ]
    )

    let argumentsPackage = fixturePath("BenchmarkTestingArgumentsPackage")
    let argumentsScratch = scratchPath("fixture-benchmark-testing-arguments")
    try? FileManager.default.removeItem(atPath: argumentsScratch)
    try FileManager.default.createDirectory(
      atPath: argumentsScratch,
      withIntermediateDirectories: true
    )
    let argumentsList = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "swift",
        "package",
        "-q",
        "--package-path",
        argumentsPackage,
        "--scratch-path",
        argumentsScratch,
        "--allow-writing-to-directory",
        argumentsScratch,
        "benchmark",
        "list",
        "--format",
        "json",
      ]
    )

    #expect(privateFailure.contains("private/fileprivate benchmark declarations cannot be bridged"))
    #expect(privateFailure.contains("make them internal"))
    #expect(argumentsList.contains("\"dimensionSizes\""))
    #expect(argumentsList.contains("1"))
    #expect(argumentsList.contains("2"))
  }

  private func runProcess(executable: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let errorOutput = String(
      decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw PackageWorkflowError(
        status: process.terminationStatus,
        output: output,
        errorOutput: errorOutput
      )
    }
    return output
  }

  private func runProcessFailure(executable: String, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let errorOutput = String(
      decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus != 0 else {
      throw PackageWorkflowError(
        status: process.terminationStatus,
        output: output,
        errorOutput: "Expected process to fail but it succeeded."
      )
    }
    return "\(output)\n\(errorOutput)"
  }

  private func cliPath() throws -> String {
    #if DEBUG
      let configuration = "debug"
    #else
      let configuration = "release"
    #endif
    let path =
      ProcessInfo.processInfo.environment["SWIFT_BENCHMARK_CLI_PATH"]
      ?? repositoryRoot().appendingPathComponent(".build/\(configuration)/swift-benchmark-cli").path
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw PackageWorkflowError(
        status: 127, output: "", errorOutput: "Missing active CLI executable: \(path)")
    }
    return path
  }

  private func fixturePackagePath() -> String {
    fixturePath("BenchmarkPackage")
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func fixturePath(_ name: String) -> String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/\(name)")
      .path
  }

  private func scratchPath(_ name: String) -> String {
    repositoryRoot()
      .appendingPathComponent(".build/\(name)")
      .path
  }

  private func writeCModuleDependencyPackage(at package: URL) throws {
    try writeFile(
      """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "CModuleDependency",
        products: [
          .library(name: "CModuleDependency", targets: ["CModuleDependency"])
        ],
        targets: [
          .target(
            name: "CModuleDependency",
            path: "Sources/CModuleDependency",
            publicHeadersPath: "include"
          )
        ]
      )
      """,
      to: package.appendingPathComponent("Package.swift")
    )
    try writeFile(
      """
      #ifndef CMODULE_DEPENDENCY_H
      #define CMODULE_DEPENDENCY_H

      int c_module_dependency_value(void);

      #endif
      """,
      to: package.appendingPathComponent(
        "Sources/CModuleDependency/include/CModuleDependency.h"
      )
    )
    try writeFile(
      """
      module CModuleDependency {
        header "CModuleDependency.h"
        export *
      }
      """,
      to: package.appendingPathComponent(
        "Sources/CModuleDependency/include/module.modulemap"
      )
    )
    try writeFile(
      """
      #include "CModuleDependency.h"

      int c_module_dependency_value(void) {
        return 42;
      }
      """,
      to: package.appendingPathComponent("Sources/CModuleDependency/CModuleDependency.c")
    )
  }

  private func initializeGitRepository(at directory: URL) throws {
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", directory.path, "init", "-q"]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", directory.path, "checkout", "-q", "-B", "main"]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: ["git", "-C", directory.path, "add", "."]
    )
    _ = try runProcess(
      executable: "/usr/bin/env",
      arguments: [
        "git",
        "-C",
        directory.path,
        "-c",
        "user.name=swift-benchmark-tests",
        "-c",
        "user.email=swift-benchmark-tests@example.invalid",
        "commit",
        "-q",
        "-m",
        "Initial test fixture",
      ]
    )
  }

  private func writeCModuleBenchmarkPackage(
    at package: URL,
    dependency: URL,
    swiftBenchmarkRoot: URL
  ) throws {
    let dependencyURL = dependency.absoluteURL
    try writeFile(
      """
      // swift-tools-version: 6.0
      import PackageDescription

      let package = Package(
        name: "CModuleBenchmarkPackage",
        platforms: [.macOS(.v15)],
        dependencies: [
          .package(path: \(swiftStringLiteral(swiftBenchmarkRoot.path))),
          .package(url: \(swiftStringLiteral(dependencyURL.absoluteString)), branch: "main")
        ],
        targets: [
          .target(
            name: "CModuleBenchmarkLibrary",
            dependencies: [
              .product(name: "Benchmark", package: "swift-benchmark"),
              .product(name: "CModuleDependency", package: "CModuleDependency")
            ]
          )
        ]
      )
      """,
      to: package.appendingPathComponent("Package.swift")
    )
    try writeFile(
      """
      import Benchmark
      import CModuleDependency

      @BenchmarkSuite("CModuleFixture", .tag("cModule"))
      struct CModuleFixtureBenchmarks {
        @Benchmark("CModuleNoop")
        func noop() {
          blackHole(c_module_dependency_value())
        }
      }
      """,
      to: package.appendingPathComponent(
        "Sources/CModuleBenchmarkLibrary/LibraryBenchmarks.swift"
      )
    )
  }

  private func writeFile(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func swiftStringLiteral(_ value: String) -> String {
    var escaped = ""
    for character in value {
      switch character {
      case "\\":
        escaped += "\\\\"
      case "\"":
        escaped += "\\\""
      case "\n":
        escaped += "\\n"
      case "\r":
        escaped += "\\r"
      case "\t":
        escaped += "\\t"
      default:
        escaped.append(character)
      }
    }
    return "\"\(escaped)\""
  }

  private func writeFakeXcrun(to path: String) throws {
    let script = """
      #!/bin/sh
      output=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--output" ]; then
          shift
          output="$1"
        fi
        shift
      done
      if [ -n "$output" ]; then
        mkdir -p "$output"
      fi
      exit 0
      """
    try script.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: path
    )
  }
}

private struct PackageWorkflowError: Error, CustomStringConvertible {
  var status: Int32
  var output: String
  var errorOutput: String

  var description: String {
    "process failed with status \(status)\nstdout:\n\(output)\nstderr:\n\(errorOutput)"
  }
}
