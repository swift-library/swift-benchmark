// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import PackagePlugin

/// `swift package benchmark <command>`: builds a benchmark host from the
/// package's declarations and hands it to the CLI, unless the arguments name a
/// host already. Where heap counting works, on Apple platforms and Linux with
/// glibc, it also builds and passes the interposer library.
@main
struct BenchmarkPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let cliTool = try context.tool(named: "BenchmarkCLI")
    guard let command = arguments.first, ["list", "run", "check", "trace"].contains(command),
      !arguments.contains("--host")
    else {
      try runProcess(executable: cliTool.url, arguments: arguments)
      return
    }

    let builder = try HostBuilder(
      context: context, cliTool: cliTool, packageManager: packageManager)
    let host = try builder.build()
    var hostArguments = [command, "--host", host.path]
    if command != "list" {
      hostArguments += ["--swift-version", try builder.compilerVersion()]
      #if canImport(Darwin) || canImport(Glibc)
        hostArguments += ["--interposer", try builder.buildInterposer().path]
      #endif
    }
    try runProcess(executable: cliTool.url, arguments: hostArguments + arguments.dropFirst())
  }
}
