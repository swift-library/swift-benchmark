// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

extension HostBuilder {
  /// Arguments for what the discovered targets link besides object files:
  /// the macOS slice of each XCFramework binary target, and the C++ standard
  /// library when a C++ or Objective-C++ target is involved.
  func nativeLibraryArguments(discoveredTargetNames: [String]) throws -> [String] {
    let dependencies = context.package.sourceModules
      .filter { discoveredTargetNames.contains($0.name) }
      .flatMap { [$0 as any Target] + $0.recursiveTargetDependencies }

    var arguments: [String] = []
    var seen: Set<String> = []
    for target in dependencies where seen.insert(target.id).inserted {
      if let binary = target as? BinaryArtifactTarget, binary.kind == .xcframework {
        arguments += try XCFrameworkSlice(binary.artifactURL).arguments
      }
    }
    let cxxExtensions: Set<String> = ["cpp", "cc", "cxx", "c++", "mm"]
    let usesCxx = dependencies.contains { target in
      (target as? ClangSourceModuleTarget)?.sourceFiles.contains {
        cxxExtensions.contains($0.url.pathExtension.lowercased())
      } == true
    }
    return arguments + (usesCxx ? ["-lc++"] : [])
  }
}

/// The library of an XCFramework built for macOS on this machine's
/// architecture, as its `Info.plist` lists it.
private struct XCFrameworkSlice {
  var directory: URL
  var libraryPath: String
  var headersPath: String?

  init(_ xcframework: URL) throws {
    let infoURL = xcframework.appendingPathComponent("Info.plist")
    let plist =
      try PropertyListSerialization.propertyList(
        from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
    let libraries = plist?["AvailableLibraries"] as? [[String: Any]] ?? []
    #if arch(arm64)
      let architecture = "arm64"
    #else
      let architecture = "x86_64"
    #endif
    guard
      let library = libraries.first(where: { library in
        library["SupportedPlatform"] as? String == "macos"
          && library["SupportedPlatformVariant"] == nil
          && (library["SupportedArchitectures"] as? [String] ?? []).contains(architecture)
      }),
      let identifier = library["LibraryIdentifier"] as? String,
      let libraryPath = library["LibraryPath"] as? String
    else {
      throw PluginError.unsupportedBinaryTarget(xcframework.path, architecture: architecture)
    }
    directory = xcframework.appendingPathComponent(identifier)
    self.libraryPath = libraryPath
    headersPath = library["HeadersPath"] as? String
  }

  var arguments: [String] {
    let library = directory.appendingPathComponent(libraryPath)
    let rpath = ["-Xlinker", "-rpath", "-Xlinker", directory.path]
    switch library.pathExtension {
    case "framework":
      let name = library.deletingPathExtension().lastPathComponent
      return ["-F", directory.path, "-framework", name] + rpath
    case "dylib":
      return headerArguments + [library.path] + rpath
    default:
      return headerArguments + [library.path]
    }
  }

  /// The slice's headers directory, where the importer finds its module map.
  private var headerArguments: [String] {
    headersPath.map { ["-I", directory.appendingPathComponent($0).path] } ?? []
  }
}
