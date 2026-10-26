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

    // Only targets that declare benchmarks are built, with their
    // dependencies; other targets, such as UI tests, are left alone. A
    // release build compiles test targets for testing, which the bridge's
    // `@testable import` needs, only when it builds every test target.
    let subsets: [PackageManager.BuildSubset] =
      configuration == .release && plan.requiresSwiftTesting
      ? [.all(includingTests: true)]
      : plan.discoveredTargetNames.map { .target($0) }
    for subset in subsets {
      let build = try packageManager.build(subset, parameters: parameters)
      guard build.succeeded else {
        throw PluginError.buildFailed(build.logText)
      }
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
    #if os(Linux)
      // Allocation sites name functions through the dynamic symbol table,
      // which holds an executable's own functions only when exported.
      let symbolArguments = ["-Xlinker", "--export-dynamic"]
    #else
      let symbolArguments: [String] = []
    #endif

    try runProcess(
      executable: swiftc,
      arguments: optimization + symbolArguments + [
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

  /// Builds the interposer library, which the CLI loads into the processes
  /// that count each step's allocations.
  func buildInterposer() throws -> URL {
    let build = try packageManager.build(
      .product("_BenchmarkInterposer"), parameters: parameters)
    guard build.succeeded,
      let library = build.builtArtifacts.first(where: { $0.kind == .dynamicLibrary })
    else {
      throw PluginError.buildFailed(build.logText)
    }
    return library.url
  }

  private var parameters: PackageManager.BuildParameters {
    PackageManager.BuildParameters(configuration: configuration, logging: .concise, echoLogs: false)
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
