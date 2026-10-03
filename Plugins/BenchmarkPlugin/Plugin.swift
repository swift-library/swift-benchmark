// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

@main
struct BenchmarkPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let cliTool = try context.tool(named: "BenchmarkCLI")
    guard shouldGenerateHost(for: arguments) else {
      try runProcess(executable: cliTool.url, arguments: arguments)
      return
    }

    let discoveryTool = try context.tool(named: "BenchmarkDiscoveryTool")
    let host = try buildGeneratedHost(
      context: context,
      cliTool: cliTool,
      discoveryTool: discoveryTool
    )
    guard let command = arguments.first else {
      try runProcess(executable: cliTool.url, arguments: arguments)
      return
    }
    try runProcess(
      executable: cliTool.url,
      arguments: [command, "--host", host.path] + Array(arguments.dropFirst()),
      environment: [
        "SWIFT_BENCHMARK_BUILD_CONFIGURATION": buildConfigurationName(
          matching: cliTool.url
        )
      ]
    )
  }

  private func shouldGenerateHost(for arguments: [String]) -> Bool {
    guard let command = arguments.first else {
      return false
    }
    guard ["list", "run", "check", "trace"].contains(command) else {
      return false
    }
    return !arguments.contains("--host")
  }

  private func buildGeneratedHost(
    context: PluginContext,
    cliTool: PluginContext.Tool,
    discoveryTool: PluginContext.Tool
  ) throws -> URL {
    let plan = try discoverBenchmarks(context: context, discoveryTool: discoveryTool)
    guard !plan.isEmpty else {
      throw PluginError.noBenchmarksDiscovered
    }

    let configuration = buildConfiguration(matching: cliTool.url)
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

    let buildDirectory = cliTool.url.deletingLastPathComponent()
    let host = context.pluginWorkDirectoryURL.appendingPathComponent("generated-benchmark-host")
    let moduleCache = context.pluginWorkDirectoryURL.appendingPathComponent("ModuleCache")
    try FileManager.default.createDirectory(at: moduleCache, withIntermediateDirectories: true)
    let objectFiles = try objectFiles(
      forTargetNames: plan.discoveredTargetNames,
      in: context.package,
      buildDirectory: buildDirectory,
      workDirectory: context.pluginWorkDirectoryURL
    )
    let generatedSources =
      [URL(fileURLWithPath: plan.generatedHostSourcePath)]
      + plan.testingBridges.map { URL(fileURLWithPath: $0.sourcePath) }
    let testingArguments =
      plan.requiresSwiftTesting
      ? try swiftTestingLibraryArguments() + testSupportLibraryArguments()
      : []
    let moduleMapArguments = moduleMapImportArguments(
      package: context.package,
      discoveredTargetNames: plan.discoveredTargetNames,
      packageDirectory: context.package.directoryURL,
      buildDirectory: buildDirectory
    )
    let modulesDirectory = buildDirectory.appendingPathComponent("Modules")
    // SwiftPM's separate Modules directory avoids importing compatibility
    // modulemaps from both library and macro-tool build directories.
    let swiftModuleDirectory =
      FileManager.default.fileExists(atPath: modulesDirectory.path)
      ? modulesDirectory : buildDirectory

    try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/env"),
      arguments: [
        "swiftc",
        "-parse-as-library",
        "-enable-testing",
        "-module-cache-path",
        moduleCache.path,
        "-I",
        swiftModuleDirectory.path,
        "-o",
        host.path,
      ] + moduleMapArguments + testingArguments + generatedSources.map(\.path)
        + objectFiles.map(\.path),
      captureOutputOnFailure: true
    )
    return host
  }

  private func buildConfiguration(
    matching toolURL: URL
  ) -> PackageManager.BuildConfiguration {
    let buildDirectory = toolURL.deletingLastPathComponent().standardizedFileURL
    let buildRoot = swiftPMBuildRoot(containing: buildDirectory)
    var current = buildDirectory

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

  private func buildConfigurationName(matching toolURL: URL) -> String {
    buildConfiguration(matching: toolURL) == .release ? "release" : "debug"
  }

  private func moduleMapImportArguments(
    package: Package,
    discoveredTargetNames: [String],
    packageDirectory: URL,
    buildDirectory: URL
  ) -> [String] {
    let searchRoots =
      moduleMapCheckoutRoots(
        packageDirectory: packageDirectory,
        buildDirectory: buildDirectory
      )
      + moduleMapSourceRoots(
        forTargetNames: discoveredTargetNames,
        in: package,
        buildDirectory: buildDirectory
      )
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

      for case let file as URL in enumerator
      where file.pathExtension == "modulemap" {
        if let moduleName = moduleMapName(at: file) {
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

  private func moduleMapSourceRoots(
    forTargetNames discoveredTargetNames: [String],
    in package: Package,
    buildDirectory: URL
  ) -> [URL] {
    var sourceTargetsByName: [String: any SourceModuleTarget] = [:]
    for target in package.sourceModules {
      sourceTargetsByName[target.name] = target
    }

    var roots: [URL] = []
    var seen: Set<String> = []

    func appendSourceModule(_ module: any SourceModuleTarget) {
      guard let clang = module as? ClangSourceModuleTarget else {
        return
      }
      if let headers = clang.publicHeadersDirectoryURL {
        appendUnique(headers, to: &roots, seen: &seen)
      }
      if let root = sourceRoot(for: clang) {
        appendUnique(root, to: &roots, seen: &seen)
      }
      for directory in targetBuildDirectories(named: clang.name, buildDirectory: buildDirectory) {
        appendUnique(directory, to: &roots, seen: &seen)
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

  private func sourceRoot(for module: any SourceModuleTarget) -> URL? {
    let directories = module.sourceFiles
      .filter { $0.type == .source }
      .map { $0.url.deletingLastPathComponent().standardizedFileURL }
    guard !directories.isEmpty else {
      return nil
    }

    var commonComponents = directories[0].pathComponents
    for directory in directories.dropFirst() {
      commonComponents = Array(
        zip(commonComponents, directory.pathComponents)
          .prefix { $0 == $1 }
          .map(\.0)
      )
      if commonComponents.isEmpty {
        return nil
      }
    }

    return URL(fileURLWithPath: NSString.path(withComponents: commonComponents))
  }

  private func moduleMapCheckoutRoots(
    packageDirectory: URL,
    buildDirectory: URL
  ) -> [URL] {
    let packageBuildDirectory = packageDirectory.appendingPathComponent(".build")
    let activeBuildRoot = swiftPMBuildRoot(containing: buildDirectory)
    var roots: [URL] = []
    var seen: Set<String> = []

    if let activeBuildRoot {
      appendUnique(
        activeBuildRoot.appendingPathComponent("checkouts"),
        to: &roots,
        seen: &seen
      )
    }

    let shouldSearchPackageBuildRoot =
      activeBuildRoot.map {
        samePath($0, packageBuildDirectory)
      } ?? true
    if shouldSearchPackageBuildRoot {
      appendUnique(
        packageBuildDirectory.appendingPathComponent("checkouts"),
        to: &roots,
        seen: &seen
      )
      for root in nestedCheckoutRoots(in: packageBuildDirectory) {
        appendUnique(root, to: &roots, seen: &seen)
      }
    }

    return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private func swiftPMBuildRoot(containing buildDirectory: URL) -> URL? {
    var current = buildDirectory.standardizedFileURL
    for _ in 0..<8 {
      if FileManager.default.fileExists(
        atPath: current.appendingPathComponent("workspace-state.json").path
      )
        || FileManager.default.fileExists(
          atPath: current.appendingPathComponent("checkouts").path
        )
        || FileManager.default.fileExists(
          atPath: current.appendingPathComponent("repositories").path
        )
      {
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

  private func nestedCheckoutRoots(in buildDirectory: URL) -> [URL] {
    guard
      let buildEntries = try? FileManager.default.contentsOfDirectory(
        at: buildDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      return []
    }

    return buildEntries.map { $0.appendingPathComponent("checkouts") }
  }

  private func appendUnique(_ url: URL, to urls: inout [URL], seen: inout Set<String>) {
    let path = url.standardizedFileURL.path
    if seen.insert(path).inserted {
      urls.append(url)
    }
  }

  private func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
  }

  private func moduleMapName(at file: URL) -> String? {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else {
      return nil
    }
    for line in text.split(separator: "\n").prefix(8) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
      var index = 0
      if parts.indices.contains(index), parts[index] == "explicit" {
        index += 1
      }
      if parts.indices.contains(index), parts[index] == "framework" {
        index += 1
      }
      if parts.indices.contains(index + 1), parts[index] == "module" {
        return normalizedModuleName(parts[index + 1])
      }
    }
    return nil
  }

  private func normalizedModuleName(_ token: Substring) -> String {
    let trimmed = token.trimmingCharacters(
      in: CharacterSet(charactersIn: "\"'")
    )
    if let index = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) {
      return String(trimmed[..<index])
    }
    return trimmed
  }

  private func discoverBenchmarks(
    context: PluginContext,
    discoveryTool: PluginContext.Tool
  ) throws -> BenchmarkDiscoveryPlan {
    let manifest = TargetManifest(
      targets: context.package.sourceModules.map { target in
        TargetDescription(
          name: target.name,
          moduleName: target.moduleName,
          kind: targetKind(target),
          sourcePaths: target.sourceFiles
            .filter { $0.type == .source && $0.url.pathExtension == "swift" }
            .map(\.url.path)
            .sorted()
        )
      }
    )

    let manifestURL = context.pluginWorkDirectoryURL
      .appendingPathComponent("benchmark-discovery-targets.json")
    let planURL = context.pluginWorkDirectoryURL
      .appendingPathComponent("benchmark-discovery-plan.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(
      at: context.pluginWorkDirectoryURL,
      withIntermediateDirectories: true
    )
    try encoder.encode(manifest).write(to: manifestURL)
    try? FileManager.default.removeItem(at: planURL)

    _ = try runProcess(
      executable: discoveryTool.url,
      arguments: [
        "discover",
        "--targets-manifest",
        manifestURL.path,
        "--work-directory",
        context.pluginWorkDirectoryURL.path,
        "--output-plan",
        planURL.path,
      ],
      captureOutput: true,
      captureOutputOnFailure: true
    )

    let data = try Data(contentsOf: planURL)
    return try JSONDecoder().decode(BenchmarkDiscoveryPlan.self, from: data)
  }

  private func targetKind(_ target: any SourceModuleTarget) -> String {
    if target.kind == .macro {
      return "macro"
    }
    if target.kind == .snippet {
      return "snippet"
    }
    if target.kind == .test {
      return "test"
    }
    if target.kind == .executable {
      return "executable"
    }
    return "library"
  }

  private func swiftTestingLibraryArguments() throws -> [String] {
    let toolchainAttempt = "toolchain testing runtime at runtimeLibraryImportPaths.first/testing"
    let output = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/env"),
      arguments: ["swiftc", "-print-target-info"],
      captureOutput: true,
      captureOutputOnFailure: true
    )
    guard let data = output.data(using: .utf8),
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let paths = json["paths"] as? [String: Any],
      let importPaths = paths["runtimeLibraryImportPaths"] as? [String],
      let runtimeImportPath = importPaths.first
    else {
      return try swiftTestingFrameworkArguments(attempted: [toolchainAttempt])
    }
    let testingPath = URL(fileURLWithPath: runtimeImportPath)
      .appendingPathComponent("testing")
      .path
    if FileManager.default.fileExists(atPath: testingPath) {
      return [
        "-I",
        testingPath,
        "-L",
        testingPath,
        "-lTesting",
        "-Xlinker",
        "-rpath",
        "-Xlinker",
        testingPath,
      ]
    }

    return try swiftTestingFrameworkArguments(
      attempted: [toolchainAttempt, testingPath]
    )
  }

  private func swiftTestingFrameworkArguments(attempted: [String]) throws -> [String] {
    let platformPath = try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: ["--sdk", "macosx", "--show-sdk-platform-path"],
      captureOutput: true,
      captureOutputOnFailure: true
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    let frameworksPath = URL(fileURLWithPath: platformPath)
      .appendingPathComponent("Developer/Library/Frameworks")
      .path
    let testingFramework = URL(fileURLWithPath: frameworksPath)
      .appendingPathComponent("Testing.framework")
      .path
    guard FileManager.default.fileExists(atPath: testingFramework) else {
      throw PluginError.swiftTestingRuntimeUnavailable(attempted + [testingFramework])
    }
    return [
      "-F",
      frameworksPath,
      "-framework",
      "Testing",
      "-Xlinker",
      "-rpath",
      "-Xlinker",
      frameworksPath,
    ]
  }

  private func testSupportLibraryArguments() throws -> [String] {
    #if os(macOS)
      let platformPath = try runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
        arguments: ["--sdk", "macosx", "--show-sdk-platform-path"],
        captureOutput: true,
        captureOutputOnFailure: true
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      let developer = URL(fileURLWithPath: platformPath).appendingPathComponent("Developer")
      let frameworks = developer.appendingPathComponent("Library/Frameworks").path
      let libraries = developer.appendingPathComponent("usr/lib").path
      // Bridged test modules can retain XCTest adapter references and SwiftPM
      // test-entry metadata even though the generated host has its own main.
      return [
        "-F", frameworks, "-framework", "XCTest", "-L", libraries,
        "-Xlinker", "-rpath", "-Xlinker", frameworks,
        "-Xlinker", "-rpath", "-Xlinker", libraries,
      ]
    #else
      return []
    #endif
  }

  private func objectFiles(
    forTargetNames discoveredTargetNames: [String],
    in package: Package,
    buildDirectory: URL,
    workDirectory: URL
  ) throws -> [URL] {
    var sourceTargetsByName: [String: any SourceModuleTarget] = [:]
    for target in package.sourceModules {
      sourceTargetsByName[target.name] = target
    }

    var targetNames = Set(["Benchmark", "Report", "Instruments"])
    for targetName in discoveredTargetNames {
      targetNames.insert(targetName)
      guard let target = sourceTargetsByName[targetName] else {
        continue
      }
      for dependency in target.recursiveTargetDependencies {
        if let sourceModule = dependency.sourceModule {
          guard sourceModule.kind != .macro,
            sourceModule.kind != .executable,
            sourceModule.kind != .snippet
          else {
            continue
          }
          targetNames.insert(sourceModule.name)
        } else {
          targetNames.insert(dependency.name)
        }
      }
    }

    let requiredObjectNames = Set(targetNames.map { $0.lowercased() })
    let productObjects = productObjectFiles(in: buildDirectory).filter {
      requiredObjectNames.contains($0.deletingPathExtension().lastPathComponent.lowercased())
    }
    let productObjectNames = Set(
      productObjects.map {
        $0.deletingPathExtension().lastPathComponent.lowercased()
      }
    )
    var files = productObjects
    for targetName in targetNames.sorted() {
      guard !productObjectNames.contains(targetName.lowercased()) else {
        continue
      }
      for directory in targetBuildDirectories(
        named: targetName,
        buildDirectory: buildDirectory
      ) {
        files += objectFiles(in: directory)
        if let entryPoint = try sanitizedTestEntryPointObject(
          in: directory,
          targetName: targetName,
          workDirectory: workDirectory
        ) {
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

  private func objectFiles(in directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
      )
    else {
      return []
    }

    var files: [URL] = []
    for case let file as URL in enumerator
    where file.pathExtension == "o" && !isEntryPointObject(file) {
      files.append(file)
    }
    return files
  }

  private func sanitizedTestEntryPointObject(
    in directory: URL,
    targetName: String,
    workDirectory: URL
  ) throws -> URL? {
    #if os(macOS)
      guard let input = testEntryPointObject(in: directory) else {
        return nil
      }

      let symbols = workDirectory.appendingPathComponent("localized-entry-point-symbols.txt")
      try Data("_main\n".utf8).write(to: symbols)
      let output = workDirectory.appendingPathComponent(
        "\(targetName)-localized-test-entry-point.o"
      )
      try? FileManager.default.removeItem(at: output)
      try runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
        arguments: [
          "nmedit",
          "-R",
          symbols.path,
          input.path,
          "-o",
          output.path,
        ],
        captureOutputOnFailure: true
      )
      return output
    #else
      return nil
    #endif
  }

  private func testEntryPointObject(in directory: URL) -> URL? {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
      )
    else {
      return nil
    }

    for case let file as URL in enumerator
    where file.lastPathComponent == "test_entry_point.o" {
      return file
    }
    return nil
  }

  private func targetBuildDirectories(
    named targetName: String,
    buildDirectory: URL
  ) -> [URL] {
    let direct = buildDirectory.appendingPathComponent("\(targetName).build")
    if FileManager.default.fileExists(atPath: direct.path) {
      return [direct]
    }

    guard let buildRoot = swiftPMBuildRoot(containing: buildDirectory) else {
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
      let basename = directory.deletingPathExtension().lastPathComponent
        .lowercased()
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

  private func isEntryPointObject(_ file: URL) -> Bool {
    switch file.lastPathComponent {
    case "main.o", "Main.o", "main.swift.o", "test_entry_point.o":
      return true
    default:
      return false
    }
  }

  private func productObjectFiles(in buildDirectory: URL) -> [URL] {
    guard
      let products = try? FileManager.default.contentsOfDirectory(
        at: buildDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      return []
    }

    return
      products
      .filter { $0.pathExtension == "o" && !isEntryPointObject($0) }
      .sorted { $0.path < $1.path }
  }

  @discardableResult
  private func runProcess(
    executable: URL,
    arguments: [String],
    environment: [String: String] = [:],
    captureOutput: Bool = false,
    captureOutputOnFailure: Bool = false
  ) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(
      environment,
      uniquingKeysWith: { _, override in override }
    )
    let stdout = Pipe()
    let stderr = Pipe()
    if captureOutput || captureOutputOnFailure {
      process.standardOutput = stdout
    }
    if captureOutputOnFailure {
      process.standardError = stderr
    }
    try process.run()

    let outputData = CapturedProcessData()
    let errorData = CapturedProcessData()
    let readers = DispatchGroup()
    if captureOutput || captureOutputOnFailure {
      let handle = stdout.fileHandleForReading
      readers.enter()
      DispatchQueue.global().async {
        outputData.data = handle.readDataToEndOfFile()
        readers.leave()
      }
    }
    if captureOutputOnFailure {
      let handle = stderr.fileHandleForReading
      readers.enter()
      DispatchQueue.global().async {
        errorData.data = handle.readDataToEndOfFile()
        readers.leave()
      }
    }

    process.waitUntilExit()
    readers.wait()

    let output =
      (captureOutput || captureOutputOnFailure)
      ? String(decoding: outputData.data, as: UTF8.self)
      : ""
    let error =
      captureOutputOnFailure
      ? String(decoding: errorData.data, as: UTF8.self)
      : ""

    guard process.terminationStatus == 0 else {
      throw PluginError.failed(
        executable: executable.lastPathComponent,
        status: process.terminationStatus,
        output: output,
        errorOutput: error
      )
    }
    return output
  }
}

private final class CapturedProcessData: @unchecked Sendable {
  var data = Data()
}

private struct TargetManifest: Encodable {
  var targets: [TargetDescription]
}

private struct TargetDescription: Encodable {
  var name: String
  var moduleName: String
  var kind: String
  var sourcePaths: [String]
}

private struct BenchmarkDiscoveryPlan: Decodable {
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

private struct NativeDiscoveryReference: Decodable {
  var moduleName: String
  var targetName: String
  var typeName: String
  var discoveryTypeName: String
}

private struct TestingBridgeReference: Decodable {
  var moduleName: String
  var targetName: String
  var discoveryTypeName: String
  var sourcePath: String
}

enum PluginError: Error, CustomStringConvertible {
  case buildFailed(String)
  case failed(executable: String, status: Int32, output: String, errorOutput: String)
  case noBenchmarksDiscovered
  case noObjectFiles(String)
  case swiftTestingRuntimeUnavailable([String])

  var description: String {
    switch self {
    case .buildFailed(let log):
      return "Package build failed while preparing benchmark host.\n\(log)"
    case .failed(let executable, let status, let output, let errorOutput):
      let details = [output, errorOutput]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      return details.isEmpty
        ? "\(executable) exited with status \(status)."
        : "\(executable) exited with status \(status):\n\(details)"
    case .noBenchmarksDiscovered:
      return
        "No @BenchmarkSuite declarations were discovered in library targets and no @Suite(.benchmark...) or @Test(.benchmark...) declarations were discovered in test targets."
    case .noObjectFiles(let directory):
      return "No Swift object files were found under \(directory)."
    case .swiftTestingRuntimeUnavailable(let attempted):
      return """
        Swift Testing runtime was required for BenchmarkTesting bridge compilation, but no supported runtime layout was found.
        Attempted:
        \(attempted.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
  }
}
