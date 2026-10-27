// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

extension HostBuilder {
  /// Linker arguments for Swift Testing, which bridged test modules import:
  /// the toolchain's runtime when it ships one, in a `testing` directory on
  /// Apple platforms and beside the standard library on Linux, otherwise the
  /// SDK platform's `Testing.framework`.
  func swiftTestingLibraryArguments() throws -> [String] {
    let toolchainAttempt = "toolchain testing runtime at runtimeLibraryImportPaths.first/testing"
    let output = try runProcess(
      executable: swiftc,
      arguments: ["-print-target-info"],
      captureOutput: true,
      captureOutputOnFailure: true
    )
    guard let json = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
      let paths = json["paths"] as? [String: Any],
      let importPaths = paths["runtimeLibraryImportPaths"] as? [String],
      let runtimeImportPath = importPaths.first
    else {
      return try swiftTestingFrameworkArguments(attempted: [toolchainAttempt])
    }
    #if os(Linux)
      let testingPath = runtimeImportPath
      let library = URL(fileURLWithPath: testingPath).appendingPathComponent("libTesting.so").path
      guard FileManager.default.fileExists(atPath: library) else {
        throw PluginError.swiftTestingRuntimeUnavailable([library])
      }
    #else
      let testingPath = URL(fileURLWithPath: runtimeImportPath)
        .appendingPathComponent("testing")
        .path
      guard FileManager.default.fileExists(atPath: testingPath) else {
        return try swiftTestingFrameworkArguments(attempted: [toolchainAttempt, testingPath])
      }
    #endif
    return [
      "-I", testingPath, "-L", testingPath, "-lTesting",
      "-Xlinker", "-rpath", "-Xlinker", testingPath,
    ]
  }

  /// Linker arguments for XCTest, whose adapter references and test-entry
  /// metadata bridged test modules can keep.
  func testSupportLibraryArguments() throws -> [String] {
    #if os(macOS)
      let developer = URL(fileURLWithPath: try platformPath()).appendingPathComponent("Developer")
      let frameworks = developer.appendingPathComponent("Library/Frameworks").path
      let libraries = developer.appendingPathComponent("usr/lib").path
      return [
        "-F", frameworks, "-framework", "XCTest", "-L", libraries,
        "-Xlinker", "-rpath", "-Xlinker", frameworks,
        "-Xlinker", "-rpath", "-Xlinker", libraries,
      ]
    #else
      // XCTest ships beside the standard library, which the compiler links
      // from and adds to the runtime search path.
      return ["-lXCTest"]
    #endif
  }

  private func swiftTestingFrameworkArguments(attempted: [String]) throws -> [String] {
    let frameworksPath = URL(fileURLWithPath: try platformPath())
      .appendingPathComponent("Developer/Library/Frameworks")
      .path
    let testingFramework = URL(fileURLWithPath: frameworksPath)
      .appendingPathComponent("Testing.framework")
      .path
    guard FileManager.default.fileExists(atPath: testingFramework) else {
      throw PluginError.swiftTestingRuntimeUnavailable(attempted + [testingFramework])
    }
    return [
      "-F", frameworksPath, "-framework", "Testing",
      "-Xlinker", "-rpath", "-Xlinker", frameworksPath,
    ]
  }

  private func platformPath() throws -> String {
    try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: ["--sdk", "macosx", "--show-sdk-platform-path"],
      captureOutput: true,
      captureOutputOnFailure: true
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
