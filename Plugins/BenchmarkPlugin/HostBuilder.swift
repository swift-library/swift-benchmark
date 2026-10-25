// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

/// Builds the package, then links a benchmark host from the generated
/// sources and the package's object files.
///
/// The host lives in the plugin's work directory, the one place the plugin
/// sandbox lets it write. `Bundle.module` looks for resource bundles next to
/// the executable, so the build's bundles are linked there.
struct HostBuilder {
  static let hostName = "swift-benchmark-host"

  let context: PluginContext
  let packageManager: PackageManager
  /// The products directory of the build the CLI tool belongs to.
  let buildDirectory: URL
  let configuration: PackageManager.BuildConfiguration
  /// The compiler of the toolchain SwiftPM runs with.
  let swiftc: URL

  init(context: PluginContext, cliTool: PluginContext.Tool, packageManager: PackageManager) throws {
    self.context = context
    self.packageManager = packageManager
    buildDirectory = cliTool.url.deletingLastPathComponent()
    configuration = BuildLayout.configuration(of: buildDirectory)
    swiftc = try context.tool(named: "swiftc").url
  }

  func build() throws -> URL {
    let plan = try discoverBenchmarks()
    guard !plan.isEmpty else {
      throw PluginError.noBenchmarksDiscovered
    }

    let parameters = PackageManager.BuildParameters(
      configuration: configuration,
      logging: .concise,
      echoLogs: false
    )
    let build = try packageManager.build(.all(includingTests: true), parameters: parameters)
    guard build.succeeded else {
      throw PluginError.buildFailed(build.logText)
    }
    _ = try? packageManager.build(.target("Report"), parameters: parameters)

    let host = context.pluginWorkDirectoryURL.appendingPathComponent(Self.hostName)
    try linkResourceBundles(into: context.pluginWorkDirectoryURL)
    let moduleCache = context.pluginWorkDirectoryURL.appendingPathComponent("ModuleCache")
    try FileManager.default.createDirectory(at: moduleCache, withIntermediateDirectories: true)
    let objectFiles = try objectFiles(forTargetNames: plan.discoveredTargetNames)
    let generatedSources =
      [plan.generatedHostSourcePath] + plan.testingBridges.map(\.sourcePath)
    let testingArguments =
      plan.requiresSwiftTesting
      ? try swiftTestingLibraryArguments() + testSupportLibraryArguments()
      : []
    let modulesDirectory = buildDirectory.appendingPathComponent("Modules")
    // SwiftPM's separate Modules directory avoids importing compatibility
    // modulemaps from both library and macro-tool build directories.
    let swiftModuleDirectory =
      FileManager.default.fileExists(atPath: modulesDirectory.path)
      ? modulesDirectory : buildDirectory
    // Bridge closures run inside every measured batch, so they are optimized
    // like the package they call.
    let optimization = configuration == .release ? ["-O"] : []

    try runProcess(
      executable: swiftc,
      arguments: optimization + [
        "-parse-as-library",
        "-enable-testing",
        "-module-cache-path",
        moduleCache.path,
        "-I",
        swiftModuleDirectory.path,
        "-o",
        host.path,
      ] + moduleMapImportArguments(discoveredTargetNames: plan.discoveredTargetNames)
        + nativeLibraryArguments(discoveredTargetNames: plan.discoveredTargetNames)
        + testingArguments + generatedSources + objectFiles.map(\.path),
      captureOutputOnFailure: true
    )
    return host
  }

  /// Links each resource bundle of the build, `<Package>_<Target>.bundle`
  /// or `.resources`, into `directory`.
  private func linkResourceBundles(into directory: URL) throws {
    let fileManager = FileManager.default
    let products =
      (try? fileManager.contentsOfDirectory(at: buildDirectory, includingPropertiesForKeys: nil))
      ?? []
    for bundle in products where ["bundle", "resources"].contains(bundle.pathExtension) {
      let link = directory.appendingPathComponent(bundle.lastPathComponent)
      try? fileManager.removeItem(at: link)
      try fileManager.createSymbolicLink(at: link, withDestinationURL: bundle)
    }
  }

  /// The compiler's version line, such as
  /// `Apple Swift version 6.4 (swiftlang-6.4.0.12.3 clang-2100.0.12.3)`.
  func compilerVersion() throws -> String {
    let output = try runProcess(
      executable: swiftc, arguments: ["--version"], captureOutput: true,
      captureOutputOnFailure: true)
    for line in output.split(separator: "\n") {
      if let range = line.range(of: #"(Apple )?Swift version .*"#, options: .regularExpression) {
        return line[range].trimmingCharacters(in: .whitespaces)
      }
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
