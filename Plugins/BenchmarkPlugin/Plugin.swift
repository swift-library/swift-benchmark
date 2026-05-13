import Foundation
import PackagePlugin

@main
struct BenchmarkPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let tool = try context.tool(named: "BenchmarkCLI")
    guard shouldGenerateHost(for: arguments) else {
      try runProcess(executable: tool.url, arguments: arguments)
      return
    }

    let host = try buildGeneratedHost(context: context, tool: tool)
    guard let command = arguments.first else {
      try runProcess(executable: tool.url, arguments: arguments)
      return
    }
    try runProcess(
      executable: tool.url,
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
    tool: PluginContext.Tool
  ) throws -> URL {
    let plan = try benchmarkDiscoveries(
      in: context.package,
      context: context,
      tool: tool
    )
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

    let buildDirectory = tool.url.deletingLastPathComponent()
    let source = try writeGeneratedHost(plan: plan, context: context)
    let host = context.pluginWorkDirectoryURL.appendingPathComponent("generated-benchmark-host")
    let objectFiles = try objectFiles(
      for: plan.discoveredTargets,
      buildDirectory: buildDirectory
    )
    let generatedSources = [source] + plan.testingBridges.map(\.source)
    let testingArguments = plan.testingBridges.isEmpty
      ? []
      : try swiftTestingLibraryArguments()

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
      ] + testingArguments + generatedSources.map(\.path) + objectFiles.map(\.path),
      captureOutputOnFailure: true
    )
    return host
  }

  private func swiftTestingLibraryArguments() throws -> [String] {
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
      return []
    }
    let testingPath = URL(fileURLWithPath: runtimeImportPath)
      .appendingPathComponent("testing")
      .path
    guard FileManager.default.fileExists(atPath: testingPath) else {
      return []
    }
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

  private func benchmarkDiscoveries(
    in package: Package,
    context: PluginContext,
    tool: PluginContext.Tool
  ) throws -> BenchmarkDiscoveryPlan {
    var libraryDiscoveries: [BenchmarkDiscoveryReference] = []
    var testingBridges: [BenchmarkTestingBridgeReference] = []
    var skippedExecutableTargets: [String] = []
    var skippedTestTargets: [String] = []

    for target in package.sourceModules {
      guard target.kind != .macro && target.kind != .snippet else {
        continue
      }

      if target.kind == .test {
        if let bridge = try testingBridge(
          in: target,
          context: context,
          tool: tool
        ) {
          testingBridges.append(bridge)
          continue
        }
        if try !benchmarkSuiteDeclarations(in: target).isEmpty {
          skippedTestTargets.append(target.name)
        }
        continue
      }

      let declarations = try benchmarkSuiteDeclarations(in: target)
      guard !declarations.isEmpty else {
        continue
      }

      guard target.kind != .executable else {
        skippedExecutableTargets.append(target.name)
        continue
      }

      libraryDiscoveries.append(
        contentsOf: declarations.map { declaration in
          BenchmarkDiscoveryReference(
            moduleName: target.moduleName,
            target: target,
            typeName: declaration
          )
        }
      )
    }

    if libraryDiscoveries.isEmpty, testingBridges.isEmpty, !skippedExecutableTargets.isEmpty {
      throw PluginError.executableTargetRequiresHost(skippedExecutableTargets.sorted())
    }
    if libraryDiscoveries.isEmpty, testingBridges.isEmpty, !skippedTestTargets.isEmpty {
      throw PluginError.testTargetRequiresLibrary(skippedTestTargets.sorted())
    }
    return BenchmarkDiscoveryPlan(
      libraryDiscoveries: libraryDiscoveries,
      testingBridges: testingBridges
    )
  }

  private func testingBridge(
    in target: any SourceModuleTarget,
    context: PluginContext,
    tool: PluginContext.Tool
  ) throws -> BenchmarkTestingBridgeReference? {
    let sourcePaths = target.sourceFiles
      .filter { $0.type == .source && $0.url.pathExtension == "swift" }
      .map(\.url.path)
    guard !sourcePaths.isEmpty else {
      return nil
    }

    let directory = context.pluginWorkDirectoryURL.appendingPathComponent("BenchmarkTestingBridge")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let discoveryName = "__BenchmarkTestingDiscovery_\(sanitizedIdentifier(target.name))"
    let output = directory.appendingPathComponent("\(target.name).swift")
    try? FileManager.default.removeItem(at: output)

    _ = try runProcess(
      executable: tool.url,
      arguments: [
        "__testing-bridge-discovery",
        "--target-name",
        target.name,
        "--module-name",
        target.moduleName,
        "--discovery-name",
        discoveryName,
        "--output",
        output.path,
      ] + sourcePaths,
      captureOutput: true,
      captureOutputOnFailure: true
    )

    guard FileManager.default.fileExists(atPath: output.path) else {
      return nil
    }

    return BenchmarkTestingBridgeReference(
      moduleName: target.moduleName,
      target: target,
      discoveryTypeName: discoveryName,
      source: output
    )
  }

  private func benchmarkSuiteDeclarations(in target: any SourceModuleTarget) throws -> [String] {
    var declarations: [String] = []
    var seen = Set<String>()
    let typePattern = try NSRegularExpression(
      pattern: #"(?m)\b(?:struct|enum|actor|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
      options: []
    )

    for file in target.sourceFiles where file.type == .source && file.url.pathExtension == "swift" {
      let source = stripStringLiteralsAndComments(
        try String(contentsOf: file.url, encoding: .utf8)
      )
      let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
      for index in lines.indices where lines[index].contains("@BenchmarkSuite") {
        let end = lines.index(index, offsetBy: 8, limitedBy: lines.endIndex) ?? lines.endIndex
        let window = lines[index..<end].joined(separator: "\n")
        let range = NSRange(window.startIndex..<window.endIndex, in: window)
        guard let match = typePattern.firstMatch(in: window, range: range),
          let typeRange = Range(match.range(at: 1), in: window)
        else {
          continue
        }
        let declaration = String(window[typeRange])
        if seen.insert(declaration).inserted {
          declarations.append(declaration)
        }
      }
    }
    return declarations
  }

  private func stripStringLiteralsAndComments(_ source: String) -> String {
    let characters = Array(source)
    var output: [Character] = []
    var index = 0
    while index < characters.count {
      if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "/" {
        while index < characters.count, characters[index] != "\n" {
          output.append(" ")
          index += 1
        }
        continue
      }
      if characters[index] == "\"" {
        let isTriple = index + 2 < characters.count
          && characters[index + 1] == "\""
          && characters[index + 2] == "\""
        if isTriple {
          output.append(" ")
          output.append(" ")
          output.append(" ")
          index += 3
          while index < characters.count {
            if index + 2 < characters.count,
              characters[index] == "\"",
              characters[index + 1] == "\"",
              characters[index + 2] == "\""
            {
              output.append(" ")
              output.append(" ")
              output.append(" ")
              index += 3
              break
            }
            output.append(characters[index] == "\n" ? "\n" : " ")
            index += 1
          }
          continue
        }

        output.append(" ")
        index += 1
        var escaped = false
        while index < characters.count {
          let character = characters[index]
          output.append(character == "\n" ? "\n" : " ")
          index += 1
          if escaped {
            escaped = false
          } else if character == "\\" {
            escaped = true
          } else if character == "\"" {
            break
          }
        }
        continue
      }
      output.append(characters[index])
      index += 1
    }
    return String(output)
  }

  private func writeGeneratedHost(
    plan: BenchmarkDiscoveryPlan,
    context: PluginContext
  ) throws -> URL {
    let directory = context.pluginWorkDirectoryURL.appendingPathComponent("GeneratedBenchmarkHost")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("main.swift")
    let imports = Set(plan.libraryDiscoveries.map(\.moduleName)).sorted()
      .map { "import \($0)" }
      .joined(separator: "\n")
    let discoveryList = plan.discoveryExpressions
      .map { "    \($0)" }
      .joined(separator: ",\n")
    let contents = """
      import Benchmark
      import Report
      \(imports)

      @main
      struct GeneratedBenchmarkHost {
        static func main() async throws {
          try await BenchmarkHost.run(discoveries: [
      \(discoveryList)
          ])
        }
      }
      """
    try contents.write(to: source, atomically: true, encoding: .utf8)
    return source
  }

  private func objectFiles(
    for targets: [any SourceModuleTarget],
    buildDirectory: URL
  ) throws -> [URL] {
    var targetNames = Set(["Benchmark", "Report", "Instruments"])
    for target in targets {
      targetNames.insert(target.name)
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
      guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
      ) else {
        continue
      }
      for case let file as URL in enumerator
      where file.pathExtension == "o" && file.lastPathComponent != "main.swift.o" {
        files.append(file)
      }
    }
    guard !files.isEmpty else {
      throw PluginError.noObjectFiles(buildDirectory.path)
    }
    return files
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

private struct BenchmarkDiscoveryPlan {
  var libraryDiscoveries: [BenchmarkDiscoveryReference]
  var testingBridges: [BenchmarkTestingBridgeReference]

  var isEmpty: Bool {
    libraryDiscoveries.isEmpty && testingBridges.isEmpty
  }

  var discoveredTargets: [any SourceModuleTarget] {
    libraryDiscoveries.map(\.target) + testingBridges.map(\.target)
  }

  var discoveryExpressions: [String] {
    libraryDiscoveries.map { "\($0.moduleName).\($0.discoveryTypeName).self" }
      + testingBridges.map { "\($0.discoveryTypeName).self" }
  }
}

private struct BenchmarkDiscoveryReference {
  var moduleName: String
  var target: any SourceModuleTarget
  var typeName: String

  var discoveryTypeName: String {
    "__BenchmarkDiscovery_\(sanitizedIdentifier(typeName))"
  }
}

private struct BenchmarkTestingBridgeReference {
  var moduleName: String
  var target: any SourceModuleTarget
  var discoveryTypeName: String
  var source: URL
}

private func sanitizedIdentifier(_ name: String) -> String {
  let scalars = name.unicodeScalars.map { scalar -> String in
    CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
  }
  let identifier = scalars.joined()
  return identifier.isEmpty ? "BenchmarkSuite" : identifier
}

enum PluginError: Error, CustomStringConvertible {
  case buildFailed(String)
  case executableTargetRequiresHost([String])
  case failed(executable: String, status: Int32, output: String, errorOutput: String)
  case noBenchmarksDiscovered
  case noObjectFiles(String)
  case testTargetRequiresLibrary([String])

  var description: String {
    switch self {
    case .buildFailed(let log):
      return "Package build failed while preparing benchmark host.\n\(log)"
    case .executableTargetRequiresHost(let targets):
      return "Benchmark declarations were found only in executable target(s) \(targets.joined(separator: ", ")). Move production benchmark declarations to a library target for no-boilerplate package discovery, or use --host as an advanced override."
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
    case .testTargetRequiresLibrary(let targets):
      return "Benchmark declarations were found only in test target(s) \(targets.joined(separator: ", ")). Move production benchmark declarations to a library target for no-boilerplate package discovery, or use --host as an advanced override."
    }
  }
}
