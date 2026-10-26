// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

/// Where SwiftPM puts build outputs, for both the native build system's
/// `<triple>/<configuration>/<Target>.build` layout and Swift Build's
/// `out/Products` and `out/Intermediates.noindex` layout.
enum BuildLayout {
  static func configuration(of buildDirectory: URL) -> PackageManager.BuildConfiguration {
    let buildRoot = buildRoot(containing: buildDirectory.standardizedFileURL)
    var current = buildDirectory.standardizedFileURL

    for _ in 0..<8 {
      if let buildRoot, samePath(current, buildRoot) {
        break
      }
      switch current.lastPathComponent.lowercased() {
      case "release":
        return .release
      case "debug":
        return .debug
      default:
        break
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        break
      }
      current = parent
    }
    return .debug
  }

  /// The scratch directory, such as `.build`, that contains `buildDirectory`.
  static func buildRoot(containing buildDirectory: URL) -> URL? {
    var current = buildDirectory.standardizedFileURL
    for _ in 0..<8 {
      let markers = ["workspace-state.json", "checkouts", "repositories"]
      if markers.contains(where: {
        FileManager.default.fileExists(atPath: current.appendingPathComponent($0).path)
      }) {
        return current
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        return nil
      }
      current = parent
    }
    return nil
  }

  /// The directories holding a target's intermediate build products.
  static func targetBuildDirectories(named targetName: String, in buildDirectory: URL) -> [URL] {
    let direct = buildDirectory.appendingPathComponent("\(targetName).build")
    if FileManager.default.fileExists(atPath: direct.path) {
      return [direct]
    }

    guard let buildRoot = buildRoot(containing: buildDirectory) else {
      return []
    }
    let intermediates =
      buildRoot
      .appendingPathComponent("out")
      .appendingPathComponent("Intermediates.noindex")
    guard
      let enumerator = FileManager.default.enumerator(
        at: intermediates,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    let normalizedTargetName = targetName.lowercased()
    let targetPrefix = "\(normalizedTargetName)-"
    let configurationName = buildDirectory.lastPathComponent
    var directories: [URL] = []
    for case let directory as URL in enumerator {
      guard directory.pathExtension == "build" else {
        continue
      }
      let basename = directory.deletingPathExtension().lastPathComponent.lowercased()
      guard basename == normalizedTargetName || basename.hasPrefix(targetPrefix) else {
        continue
      }
      guard
        directory.pathComponents.contains(where: {
          $0.caseInsensitiveCompare(configurationName) == .orderedSame
        })
      else {
        continue
      }
      directories.append(directory)
      enumerator.skipDescendants()
    }
    return directories.sorted { $0.path < $1.path }
  }

  static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
  }

  static func appendUnique(_ url: URL, to urls: inout [URL], seen: inout Set<String>) {
    if seen.insert(url.standardizedFileURL.path).inserted {
      urls.append(url)
    }
  }
}
