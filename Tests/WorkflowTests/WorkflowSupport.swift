// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// Options every `swift package` command that runs the benchmark plugin
/// needs with this toolchain.
///
/// SwiftPM 6.3 cannot build the plugin's SwiftSyntax tool beside macros built
/// from SwiftSyntax prebuilts, so the tests turn the prebuilts off there, as
/// users of that toolchain do.
let pluginPackageOptions: [String] = {
  #if compiler(>=6.4)
    []
  #else
    ["--disable-experimental-prebuilts"]
  #endif
}()

/// The arguments of `swift package benchmark <arguments>` for the package at
/// `package`, building in `scratch`, which the plugin may also write to.
func swiftPackageBenchmark(
  _ arguments: [String],
  package: String,
  scratch: String,
  configuration: String? = nil
) -> [String] {
  ["swift", "package"] + pluginPackageOptions
    + ["-q", "--package-path", package, "--scratch-path", scratch]
    + (configuration.map { ["--configuration", $0] } ?? [])
    + ["--allow-writing-to-directory", scratch, "benchmark"] + arguments
}

func runProcess(executable: String, arguments: [String]) async throws -> String {
  let result = try await processResult(executable: executable, arguments: arguments)
  guard result.status == 0 else {
    throw PackageWorkflowError(
      status: result.status,
      output: result.output,
      errorOutput: result.errorOutput
    )
  }
  return result.output
}

func runProcessFailure(executable: String, arguments: [String]) async throws -> String {
  let result = try await processResult(executable: executable, arguments: arguments)
  guard result.status != 0 else {
    throw PackageWorkflowError(
      status: result.status,
      output: result.output,
      errorOutput: "Expected process to fail but it succeeded."
    )
  }
  return "\(result.output)\n\(result.errorOutput)"
}

/// Runs `executable` and waits for it without holding a thread, so tests
/// that run long builds in parallel do not starve the other tests.
func processResult(executable: String, arguments: [String]) async throws -> (
  status: Int32, output: String, errorOutput: String
) {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("swift-benchmark-process-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let outputURL = directory.appendingPathComponent("stdout")
  let errorURL = directory.appendingPathComponent("stderr")
  try Data().write(to: outputURL)
  try Data().write(to: errorURL)
  // File capture lets verbose cold builds finish without filling unread pipes.
  let stdout = try FileHandle(forWritingTo: outputURL)
  defer { try? stdout.close() }
  let stderr = try FileHandle(forWritingTo: errorURL)
  defer { try? stderr.close() }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = repositoryRoot()
  process.standardOutput = stdout
  process.standardError = stderr
  try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<Void, any Error>) in
    process.terminationHandler = { _ in continuation.resume() }
    do {
      try process.run()
    } catch {
      process.terminationHandler = nil
      continuation.resume(throwing: error)
    }
  }
  return (
    process.terminationStatus,
    String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
    String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
  )
}

func cliPath() throws -> String {
  #if DEBUG
    let configuration = "debug"
  #else
    let configuration = "release"
  #endif
  let path =
    ProcessInfo.processInfo.environment["SWIFT_BENCHMARK_CLI_PATH"]
    ?? repositoryRoot().appendingPathComponent(".build/\(configuration)/swift-benchmark-cli").path
  guard FileManager.default.isExecutableFile(atPath: path) else {
    throw PackageWorkflowError(
      status: 127, output: "", errorOutput: "Missing active CLI executable: \(path)")
  }
  return path
}

/// The interposer library built beside the CLI.
func interposerPath() throws -> String {
  #if canImport(Darwin)
    let name = "lib_BenchmarkInterposer.dylib"
  #else
    let name = "lib_BenchmarkInterposer.so"
  #endif
  let path = URL(fileURLWithPath: try cliPath()).deletingLastPathComponent()
    .appendingPathComponent(name).path
  guard FileManager.default.fileExists(atPath: path) else {
    throw PackageWorkflowError(
      status: 127, output: "", errorOutput: "Missing interposer library: \(path)")
  }
  return path
}

func fixturePackagePath() -> String {
  fixturePath("BenchmarkPackage")
}

func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

func fixturePath(_ name: String) -> String {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/\(name)")
    .path
}

func scratchPath(_ name: String) -> String {
  repositoryRoot()
    .appendingPathComponent(".build/\(name)")
    .path
}

func writeFile(_ contents: String, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try contents.write(to: url, atomically: true, encoding: .utf8)
}

func swiftStringLiteral(_ value: String) -> String {
  var escaped = ""
  for character in value {
    switch character {
    case "\\":
      escaped += "\\\\"
    case "\"":
      escaped += "\\\""
    case "\n":
      escaped += "\\n"
    case "\r":
      escaped += "\\r"
    case "\t":
      escaped += "\\t"
    default:
      escaped.append(character)
    }
  }
  return "\"\(escaped)\""
}

struct PackageWorkflowError: Error, CustomStringConvertible {
  var status: Int32
  var output: String
  var errorOutput: String

  var description: String {
    "process failed with status \(status)\nstdout:\n\(output)\nstderr:\n\(errorOutput)"
  }
}
