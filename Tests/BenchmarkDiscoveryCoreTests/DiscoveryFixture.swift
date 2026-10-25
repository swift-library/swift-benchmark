// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

@testable import _BenchmarkDiscoveryCore

/// Writes source files for one target into a fresh temporary directory.
struct DiscoveryFixture {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-discovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  /// A target named `name` whose sources are `files`, keyed by file name.
  func target(
    _ name: String,
    kind: String,
    files: KeyValuePairs<String, String>
  ) throws -> TargetDescription {
    let targetDirectory = directory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    let paths = try files.map { fileName, source in
      let url = targetDirectory.appendingPathComponent(fileName)
      try source.write(to: url, atomically: true, encoding: .utf8)
      return url.path
    }
    return TargetDescription(name: name, moduleName: name, kind: kind, sourcePaths: paths)
  }

  func plan(_ targets: TargetDescription...) throws -> BenchmarkDiscoveryPlan {
    try BenchmarkDiscoveryPlanner(
      manifest: TargetManifest(targets: targets),
      workDirectory: directory.appendingPathComponent("work")
    ).makePlan()
  }

  /// The suites a test target's bridge declares for `source`.
  func bridgedSuites(_ source: String) throws -> [DiscoveredSuite] {
    let target = try target("FixtureTests", kind: "test", files: ["Tests.swift": source])
    return try SourceScanner(target: target).scan().suites
  }
}
