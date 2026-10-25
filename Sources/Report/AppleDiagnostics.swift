// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// An Instruments trace on disk and how it was produced.
package struct TraceArtifact: Sendable, Equatable {
  package var tracePath: String
  package var command: [String]
  package var metadata: [String: String]

  package init(tracePath: String, command: [String] = [], metadata: [String: String] = [:]) {
    self.tracePath = tracePath
    self.command = command
    self.metadata = metadata
  }
}

package struct TraceArtifactExporter: TraceExporter {
  package var artifact: TraceArtifact
  package var requirement: DiagnosticRequirement
  private var fileExists: @Sendable (String) -> Bool

  package init(
    artifact: TraceArtifact,
    requirement: DiagnosticRequirement = .optional,
    fileExists: @escaping @Sendable (String) -> Bool = {
      FileManager.default.fileExists(atPath: $0)
    }
  ) {
    self.artifact = artifact
    self.requirement = requirement
    self.fileExists = fileExists
  }

  package func attachments(for scope: ReportScope) async -> [DiagnosticAttachment] {
    guard fileExists(artifact.tracePath) else {
      return []
    }

    var metadata = artifact.metadata
    if !artifact.command.isEmpty {
      metadata["command"] = artifact.command.joined(separator: " ")
    }

    return [
      DiagnosticAttachment(
        id: ReportID(rawValue: "attachment:trace:\(stable(artifact.tracePath))"),
        scope: scope,
        kind: .trace,
        title: "Instruments trace",
        location: artifact.tracePath,
        contentType: "application/vnd.apple.instruments.trace",
        metadata: metadata
      )
    ]
  }

  private func stable(_ value: String) -> String {
    let stableValue =
      value
      .lowercased()
      .map { character in
        character.isLetter || character.isNumber ? character : "-"
      }
      .reduce(into: "") { partial, character in
        if character == "-", partial.last == "-" {
          return
        }
        partial.append(character)
      }
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return stableValue.isEmpty ? "artifact" : stableValue
  }
}

package struct XctraceCommandResult: Sendable, Equatable {
  package var terminationStatus: Int32
  package var standardOutput: String
  package var standardError: String

  package init(
    terminationStatus: Int32,
    standardOutput: String = "",
    standardError: String = ""
  ) {
    self.terminationStatus = terminationStatus
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

package enum XctraceRecorderError: Error, CustomStringConvertible {
  case commandFailed(arguments: [String], result: XctraceCommandResult)

  package var description: String {
    switch self {
    case .commandFailed(let arguments, let result):
      return
        "xctrace command failed with status \(result.terminationStatus): \(arguments.joined(separator: " ")) \(result.standardError)"
    }
  }
}

package struct XctraceRecorder: Sendable {
  package var xcrunPath: String
  package var runner: @Sendable ([String]) async -> XctraceCommandResult

  package init(
    xcrunPath: String = "/usr/bin/xcrun",
    runner: (@Sendable ([String]) async -> XctraceCommandResult)? = nil
  ) {
    self.xcrunPath = xcrunPath
    self.runner =
      runner ?? { arguments in
        await XctraceRecorder.runProcess(xcrunPath: xcrunPath, arguments: arguments)
      }
  }

  package func record(
    executablePath: String,
    executableArguments: [String] = [],
    outputTracePath: String,
    template: String = "Time Profiler",
    metadata: [String: String] = [:]
  ) async throws -> TraceArtifact {
    var arguments = [
      "xctrace",
      "record",
      "--template",
      template,
      "--output",
      outputTracePath,
    ]
    arguments += ["--launch", executablePath, "--"] + executableArguments
    let result = await runner(arguments)
    guard result.terminationStatus == 0 else {
      throw XctraceRecorderError.commandFailed(arguments: [xcrunPath] + arguments, result: result)
    }
    var artifactMetadata = metadata
    artifactMetadata["template"] = template
    artifactMetadata["tool"] = "xctrace"
    return TraceArtifact(
      tracePath: outputTracePath,
      command: [xcrunPath] + arguments,
      metadata: artifactMetadata
    )
  }

  private static func runProcess(
    xcrunPath: String,
    arguments: [String]
  ) async -> XctraceCommandResult {
    #if os(macOS) || os(Linux)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: xcrunPath)
      process.arguments = arguments
      let stdout = Pipe()
      let stderr = Pipe()
      process.standardOutput = stdout
      process.standardError = stderr
      do {
        try process.run()
        let output = PipeCapture()
        let errorOutput = PipeCapture()
        output.startReading(stdout.fileHandleForReading)
        errorOutput.startReading(stderr.fileHandleForReading)
        process.waitUntilExit()
        return XctraceCommandResult(
          terminationStatus: process.terminationStatus,
          standardOutput: output.string(),
          standardError: errorOutput.string()
        )
      } catch {
        return XctraceCommandResult(
          terminationStatus: 127,
          standardError: String(describing: error)
        )
      }
    #else
      return XctraceCommandResult(
        terminationStatus: 127,
        standardError: "xctrace process execution requires a supported host platform."
      )
    #endif
  }
}
