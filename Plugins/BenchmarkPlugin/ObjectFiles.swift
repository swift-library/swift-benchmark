// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

extension HostBuilder {
  /// The object files of the discovered targets, everything they depend on,
  /// and the benchmark libraries, without any executable entry point.
  func objectFiles(forTargetNames discoveredTargetNames: [String]) throws -> [URL] {
    var sourceTargetsByName: [String: any SourceModuleTarget] = [:]
    for target in context.package.sourceModules {
      sourceTargetsByName[target.name] = target
    }

    var targetNames = Set(["Benchmark", "Report", "Instruments"])
    for targetName in discoveredTargetNames {
      targetNames.insert(targetName)
      guard let target = sourceTargetsByName[targetName] else {
        continue
      }
      for dependency in target.recursiveTargetDependencies {
        guard let sourceModule = dependency.sourceModule else {
          targetNames.insert(dependency.name)
          continue
        }
        if ![.macro, .executable, .snippet].contains(sourceModule.kind) {
          targetNames.insert(sourceModule.name)
        }
      }
    }

    // A product build may link a target into one `<Target>.o` in the
    // products directory instead of leaving per-file objects.
    let requiredObjectNames = Set(targetNames.map { $0.lowercased() })
    let productObjects = productObjectFiles().filter {
      requiredObjectNames.contains($0.deletingPathExtension().lastPathComponent.lowercased())
    }
    let productObjectNames = Set(
      productObjects.map { $0.deletingPathExtension().lastPathComponent.lowercased() })
    var files = productObjects
    for targetName in targetNames.sorted()
    where !productObjectNames.contains(targetName.lowercased()) {
      for directory in BuildLayout.targetBuildDirectories(named: targetName, in: buildDirectory) {
        files += Self.objectFiles(in: directory)
        if let entryPoint = try localizedTestEntryPoint(in: directory, targetName: targetName) {
          files.append(entryPoint)
        }
      }
    }
    files = Array(Dictionary(grouping: files, by: \.path).values.compactMap(\.first))
    guard !files.isEmpty else {
      throw PluginError.noObjectFiles(buildDirectory.path)
    }
    return files
  }

  private func productObjectFiles() -> [URL] {
    let products =
      (try? FileManager.default.contentsOfDirectory(
        at: buildDirectory, includingPropertiesForKeys: nil)) ?? []
    return
      products
      .filter { $0.pathExtension == "o" && !Self.isEntryPoint($0) }
      .sorted { $0.path < $1.path }
  }

  /// A copy of a test target's `test_entry_point.o` with its `_main` made
  /// local. Bridged test modules can keep references to SwiftPM's test-entry
  /// metadata, but the host has its own `main`.
  private func localizedTestEntryPoint(in directory: URL, targetName: String) throws -> URL? {
    #if os(macOS)
      guard
        let input = Self.files(in: directory).first(where: {
          $0.lastPathComponent == "test_entry_point.o"
        })
      else {
        return nil
      }
      let workDirectory = context.pluginWorkDirectoryURL
      let symbols = workDirectory.appendingPathComponent("localized-entry-point-symbols.txt")
      try Data("_main\n".utf8).write(to: symbols)
      let output = workDirectory.appendingPathComponent(
        "\(targetName)-localized-test-entry-point.o")
      try? FileManager.default.removeItem(at: output)
      try runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
        arguments: ["nmedit", "-R", symbols.path, input.path, "-o", output.path],
        captureOutputOnFailure: true
      )
      return output
    #else
      return nil
    #endif
  }

  private static func objectFiles(in directory: URL) -> [URL] {
    files(in: directory).filter { $0.pathExtension == "o" && !isEntryPoint($0) }
  }

  private static func files(in directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil)
    else {
      return []
    }
    return enumerator.compactMap { $0 as? URL }
  }

  private static func isEntryPoint(_ file: URL) -> Bool {
    ["main.o", "Main.o", "main.swift.o", "test_entry_point.o"].contains(file.lastPathComponent)
  }
}
