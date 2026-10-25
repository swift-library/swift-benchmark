// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// Scans every target and writes the generated host and bridge sources.
///
/// Library targets contribute `@BenchmarkSuite` types; test targets contribute
/// Swift Testing declarations enrolled with `.benchmark(...)` or written with
/// `@Benchmark`. Executable targets cannot be imported by the host, so their
/// declarations need the `--host` override.
struct BenchmarkDiscoveryPlanner {
  var manifest: TargetManifest
  var workDirectory: URL

  func makePlan() throws -> BenchmarkDiscoveryPlan {
    var nativeDiscoveries: [NativeDiscoveryReference] = []
    var testingBridges: [TestingBridgeReference] = []
    var skippedExecutableTargets: [String] = []
    var skippedTestTargets: [String] = []
    var diagnostics: [String] = []

    for target in manifest.targets where !target.isMacro && !target.isSnippet {
      let scan = try SourceScanner(target: target).scan()
      diagnostics.append(contentsOf: scan.diagnostics)

      if target.isTest {
        if !scan.suites.isEmpty {
          testingBridges.append(try writeTestingBridge(for: target, suites: scan.suites))
        } else if !scan.nativeDeclarations.isEmpty {
          skippedTestTargets.append(target.name)
        }
        continue
      }

      guard !scan.nativeDeclarations.isEmpty else {
        continue
      }
      guard !target.isExecutable else {
        skippedExecutableTargets.append(target.name)
        continue
      }
      nativeDiscoveries.append(
        contentsOf: scan.nativeDeclarations.map { declaration in
          NativeDiscoveryReference(
            moduleName: target.moduleName,
            targetName: target.name,
            typeName: declaration.typeName,
            discoveryTypeName: declaration.discoveryTypeName
          )
        }
      )
    }

    if !diagnostics.isEmpty {
      throw ToolError.diagnostics(diagnostics)
    }
    if nativeDiscoveries.isEmpty, testingBridges.isEmpty {
      if !skippedExecutableTargets.isEmpty {
        throw ToolError.diagnostics([onlyIn("executable", skippedExecutableTargets)])
      }
      if !skippedTestTargets.isEmpty {
        throw ToolError.diagnostics([onlyIn("test", skippedTestTargets)])
      }
    }

    let discoveryExpressions =
      nativeDiscoveries.map { "\($0.moduleName).\($0.discoveryTypeName).self" }
      + testingBridges.map { "\($0.discoveryTypeName).self" }
    let hostSourcePath = try writeGeneratedBenchmarkHost(
      workDirectory: workDirectory,
      importedModules: nativeDiscoveries.map(\.moduleName),
      discoveryExpressions: discoveryExpressions
    )
    return BenchmarkDiscoveryPlan(
      nativeDiscoveries: nativeDiscoveries,
      testingBridges: testingBridges,
      generatedHostSourcePath: hostSourcePath.path,
      discoveredTargetNames: Set(
        nativeDiscoveries.map(\.targetName) + testingBridges.map(\.targetName)
      ).sorted(),
      requiresSwiftTesting: !testingBridges.isEmpty,
      discoveryExpressions: discoveryExpressions
    )
  }

  private func onlyIn(_ kind: String, _ targets: [String]) -> String {
    "Benchmark declarations were found only in \(kind) target(s) \(targets.sorted().joined(separator: ", ")). Move production benchmark declarations to a library target for no-boilerplate package discovery, or use --host as an advanced override."
  }

  private func writeTestingBridge(
    for target: TargetDescription,
    suites: [DiscoveredSuite]
  ) throws -> TestingBridgeReference {
    let directory = workDirectory.appendingPathComponent("BenchmarkTestingBridge")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let discoveryName = "__BenchmarkTestingDiscovery_\(sanitizedIdentifier(target.name))"
    let outputURL = directory.appendingPathComponent("\(sanitizedIdentifier(target.name)).swift")
    let source = BridgeSourceGenerator(
      moduleName: target.moduleName,
      discoveryName: discoveryName,
      suites: suites
    ).render()
    try source.write(to: outputURL, atomically: true, encoding: .utf8)
    return TestingBridgeReference(
      moduleName: target.moduleName,
      targetName: target.name,
      discoveryTypeName: discoveryName,
      sourcePath: outputURL.path
    )
  }
}
