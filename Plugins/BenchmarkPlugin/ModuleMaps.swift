// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

extension HostBuilder {
  /// Compiler arguments that make the C modules the discovered targets
  /// depend on importable from the host's sources: each module map found in
  /// dependency checkouts, the targets' public headers, and their build
  /// directories, with its directory on the include path.
  func moduleMapImportArguments(discoveredTargetNames: [String]) -> [String] {
    let searchRoots =
      moduleMapCheckoutRoots() + moduleMapSourceRoots(forTargetNames: discoveredTargetNames)
    var moduleMapsByName: [String: String] = [:]
    var anonymousModuleMaps: Set<String> = []

    for root in searchRoots {
      guard
        FileManager.default.fileExists(atPath: root.path),
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
      else {
        continue
      }
      for case let file as URL in enumerator where file.pathExtension == "modulemap" {
        if let moduleName = Self.moduleName(declaredIn: file) {
          moduleMapsByName[moduleName] = moduleMapsByName[moduleName] ?? file.path
        } else {
          anonymousModuleMaps.insert(file.path)
        }
      }
    }

    let moduleMaps = Set(moduleMapsByName.values).union(anonymousModuleMaps).sorted()
    let includeDirectories = Set(
      moduleMaps.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
    )
    return includeDirectories.sorted().flatMap { ["-I", $0] }
      + moduleMaps.flatMap { ["-Xcc", "-fmodule-map-file=\($0)"] }
  }

  private func moduleMapSourceRoots(forTargetNames discoveredTargetNames: [String]) -> [URL] {
    var sourceTargetsByName: [String: any SourceModuleTarget] = [:]
    for target in context.package.sourceModules {
      sourceTargetsByName[target.name] = target
    }

    var roots: [URL] = []
    var seen: Set<String> = []
    func appendSourceModule(_ module: any SourceModuleTarget) {
      guard let clang = module as? ClangSourceModuleTarget else {
        return
      }
      if let headers = clang.publicHeadersDirectoryURL {
        BuildLayout.appendUnique(headers, to: &roots, seen: &seen)
      }
      if let root = Self.sourceRoot(of: clang) {
        BuildLayout.appendUnique(root, to: &roots, seen: &seen)
      }
      for directory in BuildLayout.targetBuildDirectories(named: clang.name, in: buildDirectory) {
        BuildLayout.appendUnique(directory, to: &roots, seen: &seen)
      }
    }

    for targetName in discoveredTargetNames {
      guard let target = sourceTargetsByName[targetName] else {
        continue
      }
      appendSourceModule(target)
      for dependency in target.recursiveTargetDependencies {
        if let sourceModule = dependency.sourceModule {
          appendSourceModule(sourceModule)
        }
      }
    }
    return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  /// The checkout directories of the active build and, when the build uses
  /// the package's own `.build`, of every scratch directory inside it.
  private func moduleMapCheckoutRoots() -> [URL] {
    let packageBuildDirectory = context.package.directoryURL.appendingPathComponent(".build")
    let activeBuildRoot = BuildLayout.buildRoot(containing: buildDirectory)
    var roots: [URL] = []
    var seen: Set<String> = []

    if let activeBuildRoot {
      BuildLayout.appendUnique(
        activeBuildRoot.appendingPathComponent("checkouts"), to: &roots, seen: &seen)
    }
    let searchesPackageBuildRoot =
      activeBuildRoot.map { BuildLayout.samePath($0, packageBuildDirectory) } ?? true
    if searchesPackageBuildRoot {
      BuildLayout.appendUnique(
        packageBuildDirectory.appendingPathComponent("checkouts"), to: &roots, seen: &seen)
      let entries =
        (try? FileManager.default.contentsOfDirectory(
          at: packageBuildDirectory, includingPropertiesForKeys: nil)) ?? []
      for entry in entries {
        BuildLayout.appendUnique(entry.appendingPathComponent("checkouts"), to: &roots, seen: &seen)
      }
    }
    return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  /// The deepest directory containing all of a module's source files.
  private static func sourceRoot(of module: any SourceModuleTarget) -> URL? {
    let directories = module.sourceFiles
      .filter { $0.type == .source }
      .map { $0.url.deletingLastPathComponent().standardizedFileURL }
    guard var commonComponents = directories.first?.pathComponents else {
      return nil
    }
    for directory in directories.dropFirst() {
      commonComponents = zip(commonComponents, directory.pathComponents)
        .prefix { $0 == $1 }
        .map(\.0)
      if commonComponents.isEmpty {
        return nil
      }
    }
    return URL(fileURLWithPath: NSString.path(withComponents: commonComponents))
  }

  /// The name in a module map's first `[explicit] [framework] module <name>`
  /// declaration, if one appears in its first lines.
  private static func moduleName(declaredIn file: URL) -> String? {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else {
      return nil
    }
    for line in text.split(separator: "\n").prefix(8) {
      let parts = line.trimmingCharacters(in: .whitespaces)
        .split(whereSeparator: { $0 == " " || $0 == "\t" })
      var index = 0
      if parts.indices.contains(index), parts[index] == "explicit" {
        index += 1
      }
      if parts.indices.contains(index), parts[index] == "framework" {
        index += 1
      }
      if parts.indices.contains(index + 1), parts[index] == "module" {
        let token = parts[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if let end = token.firstIndex(where: { $0 == "{" || $0 == "[" }) {
          return String(token[..<end])
        }
        return token
      }
    }
    return nil
  }
}
