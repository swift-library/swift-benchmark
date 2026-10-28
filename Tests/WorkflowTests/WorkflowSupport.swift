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

/// Runs `executable` in the repository root and waits for it without holding
/// a thread of the cooperative pool, so tests that run long builds in
/// parallel do not starve the other tests.
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
  let status = try await childStatus(
    executable: executable, arguments: arguments, standardOutput: stdout, standardError: stderr)
  return (
    status,
    String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
    String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
  )
}

#if os(Linux)
  /// Runs the child with `posix_spawn`, which closes every descriptor above
  /// standard error in the child, and returns its exit code, or the signal
  /// that ended it.
  ///
  /// Foundation's `Process` on Linux learns that a child exited when the
  /// child's end of a socket closes. It picks the descriptors a child closes
  /// from a list read before it spawns, so a socket that another thread opens
  /// in between leaks into the new child, and that other child's exit goes
  /// unnoticed until the new child exits. The plugin workflows run builds for
  /// minutes, so a short command started beside them could wait that long.
  private func childStatus(
    executable: String, arguments: [String], standardOutput: FileHandle,
    standardError: FileHandle
  ) async throws -> Int32 {
    var actions = posix_spawn_file_actions_t()
    try spawnCheck(posix_spawn_file_actions_init(&actions))
    defer { posix_spawn_file_actions_destroy(&actions) }
    try spawnCheck(
      posix_spawn_file_actions_adddup2(&actions, standardOutput.fileDescriptor, STDOUT_FILENO))
    try spawnCheck(
      posix_spawn_file_actions_adddup2(&actions, standardError.fileDescriptor, STDERR_FILENO))
    try spawnCheck(posix_spawn_file_actions_addchdir_np(&actions, repositoryRoot().path))
    try spawnCheck(posix_spawn_file_actions_addclosefrom_np(&actions, STDERR_FILENO + 1))
    var attributes = posix_spawnattr_t()
    try spawnCheck(posix_spawnattr_init(&attributes))
    defer { posix_spawnattr_destroy(&attributes) }
    // Threads of the cooperative pool block most signals, and a child would
    // otherwise inherit the mask of the thread that spawns it.
    var unblocked = sigset_t()
    sigemptyset(&unblocked)
    try spawnCheck(posix_spawnattr_setsigmask(&attributes, &unblocked))
    try spawnCheck(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK)))
    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { for argument in argv { free(argument) } }
    var pid = pid_t()
    try spawnCheck(posix_spawn(&pid, executable, &actions, &attributes, argv, environ))
    return try await withCheckedThrowingContinuation { [pid] continuation in
      // A thread outside the cooperative pool blocks until the child exits.
      Thread {
        var status: Int32 = 0
        var waited: pid_t
        repeat { waited = waitpid(pid, &status, 0) } while waited == -1 && errno == EINTR
        guard waited == pid else { return continuation.resume(throwing: posixError(errno)) }
        let signal = status & 0x7f
        continuation.resume(returning: signal == 0 ? (status >> 8) & 0xff : signal)
      }.start()
    }
  }

  private func spawnCheck(_ result: Int32) throws {
    guard result == 0 else { throw posixError(result) }
  }

  private func posixError(_ code: Int32) -> PackageWorkflowError {
    PackageWorkflowError(status: 127, output: "", errorOutput: String(cString: strerror(code)))
  }
#else
  /// Runs the child with Foundation's `Process` and returns its exit code, or
  /// the signal that ended it.
  private func childStatus(
    executable: String, arguments: [String], standardOutput: FileHandle,
    standardError: FileHandle
  ) async throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = repositoryRoot()
    process.standardOutput = standardOutput
    process.standardError = standardError
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
    return process.terminationStatus
  }
#endif

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
