// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

extension HostBuilder {
  /// Runs the discovery tool over the package's Swift sources; it writes the
  /// host's `main.swift`, any testing bridges, and the plan describing them.
  func discoverBenchmarks() throws -> BenchmarkDiscoveryPlan {
    let discoveryTool = try context.tool(named: "BenchmarkDiscoveryTool")
    let manifest = TargetManifest(
      targets: context.package.sourceModules.map { target in
        TargetDescription(
          name: target.name,
          moduleName: target.moduleName,
          kind: Self.kind(of: target),
          sourcePaths: target.sourceFiles
            .filter { $0.type == .source && $0.url.pathExtension == "swift" }
            .map(\.url.path)
            .sorted()
        )
      }
    )

    let workDirectory = context.pluginWorkDirectoryURL
    let manifestURL = workDirectory.appendingPathComponent("benchmark-discovery-targets.json")
    let planURL = workDirectory.appendingPathComponent("benchmark-discovery-plan.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    try encoder.encode(manifest).write(to: manifestURL)
    try? FileManager.default.removeItem(at: planURL)

    try runProcess(
      executable: discoveryTool.url,
      arguments: [
        "discover",
        "--targets-manifest", manifestURL.path,
        "--work-directory", workDirectory.path,
        "--output-plan", planURL.path,
      ],
      captureOutput: true,
      captureOutputOnFailure: true
    )
    return try JSONDecoder().decode(BenchmarkDiscoveryPlan.self, from: Data(contentsOf: planURL))
  }

  private static func kind(of target: any SourceModuleTarget) -> String {
    switch target.kind {
    case .macro:
      return "macro"
    case .snippet:
      return "snippet"
    case .test:
      return "test"
    case .executable:
      return "executable"
    default:
      return "library"
    }
  }
}

/// The discovery tool's input; the shapes match `_BenchmarkDiscoveryCore`,
/// which a plugin cannot import.
struct TargetManifest: Encodable {
  var targets: [TargetDescription]
}

struct TargetDescription: Encodable {
  var name: String
  var moduleName: String
  var kind: String
  var sourcePaths: [String]
}

/// The discovery tool's output.
struct BenchmarkDiscoveryPlan: Decodable {
  var nativeDiscoveries: [NativeDiscoveryReference]
  var testingBridges: [TestingBridgeReference]
  var generatedHostSourcePath: String
  var discoveredTargetNames: [String]
  var requiresSwiftTesting: Bool
  var discoveryExpressions: [String]

  var isEmpty: Bool {
    nativeDiscoveries.isEmpty && testingBridges.isEmpty
  }
}

struct NativeDiscoveryReference: Decodable {
  var moduleName: String
  var targetName: String
  var typeName: String
  var discoveryTypeName: String
}

struct TestingBridgeReference: Decodable {
  var moduleName: String
  var targetName: String
  var discoveryTypeName: String
  var sourcePath: String
}
