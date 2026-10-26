// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// Entry point of the discovery tool the benchmark plugin runs:
/// `discover --targets-manifest <path> --work-directory <path> --output-plan <path>`.
public enum BenchmarkDiscoveryToolDriver {
  public static func run(arguments: [String]) {
    do {
      try DiscoveryCommand.run(arguments)
    } catch {
      FileHandle.standardError.write(Data("BenchmarkDiscoveryTool: \(error)\n".utf8))
      Foundation.exit(1)
    }
  }
}

enum DiscoveryCommand {
  static func run(_ arguments: [String]) throws {
    guard arguments.first == "discover" else {
      throw ToolError.invalidArguments(DiscoverOptions.usage)
    }

    let options = try DiscoverOptions(arguments: Array(arguments.dropFirst()))
    let manifestData = try Data(contentsOf: URL(fileURLWithPath: options.targetsManifestPath))
    let manifest = try JSONDecoder().decode(TargetManifest.self, from: manifestData)
    let plan = try BenchmarkDiscoveryPlanner(
      manifest: manifest,
      workDirectory: URL(fileURLWithPath: options.workDirectoryPath)
    ).makePlan()

    let outputURL = URL(fileURLWithPath: options.outputPlanPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(plan).write(to: outputURL)
  }
}

struct DiscoverOptions {
  static let usage =
    "usage: BenchmarkDiscoveryTool discover --targets-manifest <path> --work-directory <path> --output-plan <path>"

  var targetsManifestPath: String
  var workDirectoryPath: String
  var outputPlanPath: String

  init(arguments: [String]) throws {
    var targetsManifestPath: String?
    var workDirectoryPath: String?
    var outputPlanPath: String?
    var index = arguments.startIndex

    while index < arguments.endIndex {
      let argument = arguments[index]
      switch argument {
      case "--targets-manifest":
        targetsManifestPath = try Self.value(after: argument, in: arguments, index: &index)
      case "--work-directory":
        workDirectoryPath = try Self.value(after: argument, in: arguments, index: &index)
      case "--output-plan":
        outputPlanPath = try Self.value(after: argument, in: arguments, index: &index)
      default:
        throw ToolError.invalidArguments("unknown argument \(argument)")
      }
      index = arguments.index(after: index)
    }

    guard let targetsManifestPath, let workDirectoryPath, let outputPlanPath else {
      throw ToolError.invalidArguments(Self.usage)
    }
    self.targetsManifestPath = targetsManifestPath
    self.workDirectoryPath = workDirectoryPath
    self.outputPlanPath = outputPlanPath
  }

  private static func value(
    after option: String,
    in arguments: [String],
    index: inout Array<String>.Index
  ) throws -> String {
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
      throw ToolError.invalidArguments("missing value for \(option)")
    }
    index = valueIndex
    return arguments[valueIndex]
  }
}

enum ToolError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case diagnostics([String])

  var description: String {
    switch self {
    case .invalidArguments(let message):
      message
    case .diagnostics(let messages):
      messages.joined(separator: "\n")
    }
  }
}
