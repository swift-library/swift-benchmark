// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// The package's source targets, as the plugin describes them to the tool.
struct TargetManifest: Codable, Equatable {
  var targets: [TargetDescription]
}

struct TargetDescription: Codable, Equatable {
  var name: String
  var moduleName: String
  /// `library`, `executable`, `test`, `macro` or `snippet`.
  var kind: String
  var sourcePaths: [String]

  var isExecutable: Bool { kind == "executable" }
  var isMacro: Bool { kind == "macro" }
  var isSnippet: Bool { kind == "snippet" }
  var isTest: Bool { kind == "test" }
}

/// What the plugin needs to build the benchmark host; the tool writes it as
/// JSON next to the generated sources.
struct BenchmarkDiscoveryPlan: Codable, Equatable {
  var nativeDiscoveries: [NativeDiscoveryReference]
  var testingBridges: [TestingBridgeReference]
  var generatedHostSourcePath: String
  var discoveredTargetNames: [String]
  var requiresSwiftTesting: Bool
  var discoveryExpressions: [String]
}

/// A `@BenchmarkSuite` type, discoverable through the type its macro declares.
struct NativeDiscoveryReference: Codable, Equatable {
  var moduleName: String
  var targetName: String
  var typeName: String
  var discoveryTypeName: String
}

/// A generated source file that declares a test target's enrolled Swift
/// Testing suites as benchmark suites.
struct TestingBridgeReference: Codable, Equatable {
  var moduleName: String
  var targetName: String
  var discoveryTypeName: String
  var sourcePath: String
}
