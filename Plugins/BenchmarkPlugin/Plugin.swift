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
      arguments: [command, "--host", host.path] + Array(arguments.dropFirst())
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

    let parameters = PackageManager.BuildParameters(
      configuration: .debug,
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
    let objectFiles = try objectFiles(
      forTargetNames: plan.discoveredTargetNames,
      in: context.package,
      buildDirectory: buildDirectory
    )
    let generatedSources = [URL(fileURLWithPath: plan.generatedHostSourcePath)]
      + plan.testingBridges.map { URL(fileURLWithPath: $0.sourcePath) }
    let testingArguments = plan.requiresSwiftTesting
      ? try swiftTestingLibraryArguments()
      : []
    let moduleMapArguments = moduleMapImportArguments(
      packageDirectory: context.package.directoryURL,
      buildDirectory: buildDirectory
    )

    try runProcess(
      executable: URL(fileURLWithPath: "/usr/bin/env"),
      arguments: [
        "swiftc",
        "-parse-as-library",
        "-enable-testing",
        "-I",
        buildDirectory.appendingPathComponent("Modules").path,
        "-o",
        host.path,
      ] + moduleMapArguments + testingArguments + generatedSources.map(\.path)
        + objectFiles.map(\.path),
      captureOutputOnFailure: true
    )
    return host
  }

  private func moduleMapImportArguments(
    packageDirectory: URL,
    buildDirectory: URL
  ) -> [String] {
    let searchRoots = moduleMapCheckoutRoots(
      packageDirectory: packageDirectory,
      buildDirectory: buildDirectory
    )
    var includeDirectoriesByModule: [String: String] = [:]
    var anonymousIncludeDirectories: Set<String> = []

    for root in searchRoots {
      guard
        FileManager.default.fileExists(atPath: root.path),
        let enumerator = FileManager.default.enumerator(
          at: root,
          includingPropertiesForKeys: nil
        )
      else {
        continue
      }

      for case let file as URL in enumerator
      where file.lastPathComponent == "module.modulemap" {
        let includeDirectory = file.deletingLastPathComponent().path
        if let moduleName = moduleMapName(at: file) {
          includeDirectoriesByModule[moduleName] = includeDirectoriesByModule[moduleName]
            ?? includeDirectory
        } else {
          anonymousIncludeDirectories.insert(includeDirectory)
        }
      }
    }

    let includeDirectories = Set(includeDirectoriesByModule.values)
      .union(anonymousIncludeDirectories)
    return includeDirectories.sorted().flatMap { ["-I", $0] }
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

    let shouldSearchPackageBuildRoot = activeBuildRoot.map {
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
      ) || FileManager.default.fileExists(
        atPath: current.appendingPathComponent("checkouts").path
      ) || FileManager.default.fileExists(
        atPath: current.appendingPathComponent("repositories").path
      ) {
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

  private func objectFiles(
    forTargetNames discoveredTargetNames: [String],
    in package: Package,
    buildDirectory: URL
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
          targetNames.insert(sourceModule.name)
        } else {
          targetNames.insert(dependency.name)
        }
      }
    }

    var files: [URL] = []
    for targetName in targetNames.sorted() {
      let directory = buildDirectory.appendingPathComponent("\(targetName).build")
      files += objectFiles(in: directory)
    }
    files += nativeObjectFiles(in: buildDirectory)
    files = Array(Dictionary(grouping: files, by: \.path).values.compactMap(\.first))
    guard !files.isEmpty else {
      throw PluginError.noObjectFiles(buildDirectory.path)
    }
    return files
  }

  private func objectFiles(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: nil
    ) else {
      return []
    }

    var files: [URL] = []
    for case let file as URL in enumerator
    where file.pathExtension == "o" && file.lastPathComponent != "main.swift.o" {
      files.append(file)
    }
    return files
  }

  private func nativeObjectFiles(in buildDirectory: URL) -> [URL] {
    guard let targetDirectories = try? FileManager.default.contentsOfDirectory(
      at: buildDirectory,
      includingPropertiesForKeys: nil
    ) else {
      return []
    }

    return targetDirectories
      .filter { $0.pathExtension == "build" && !$0.lastPathComponent.hasSuffix("-tool.build") }
      .flatMap(objectFiles(in:))
      .filter { !$0.lastPathComponent.hasSuffix(".swift.o") }
  }

  @discardableResult
  private func runProcess(
    executable: URL,
    arguments: [String],
    captureOutput: Bool = false,
    captureOutputOnFailure: Bool = false
  ) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    if captureOutput || captureOutputOnFailure {
      process.standardOutput = stdout
    }
    if captureOutputOnFailure {
      process.standardError = stderr
    }
    try process.run()
    process.waitUntilExit()

    let output = (captureOutput || captureOutputOnFailure)
      ? String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      : ""
    let error = captureOutputOnFailure
      ? String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
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
      return "No @BenchmarkSuite declarations were discovered in library targets and no @Suite(.benchmark...) or @Test(.benchmark...) declarations were discovered in test targets."
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
