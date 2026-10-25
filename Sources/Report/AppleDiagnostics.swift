// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

public struct TraceArtifact: Sendable, Equatable {
  public var tracePath: String
  public var exportedXMLPath: String?
  public var tableOfContentsPath: String?
  public var command: [String]
  public var metadata: [String: String]

  public init(
    tracePath: String,
    exportedXMLPath: String? = nil,
    tableOfContentsPath: String? = nil,
    command: [String] = [],
    metadata: [String: String] = [:]
  ) {
    self.tracePath = tracePath
    self.exportedXMLPath = exportedXMLPath
    self.tableOfContentsPath = tableOfContentsPath
    self.command = command
    self.metadata = metadata
  }
}

public struct TraceArtifactExporter: TraceExporter {
  public var artifact: TraceArtifact
  public var requirement: DiagnosticRequirement
  private var fileExists: @Sendable (String) -> Bool

  public init(
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

  public func attachments(for scope: ReportScope) async -> [DiagnosticAttachment] {
    guard fileExists(artifact.tracePath) else {
      return []
    }

    var metadata = artifact.metadata
    if !artifact.command.isEmpty {
      metadata["command"] = artifact.command.joined(separator: " ")
    }

    var attachments = [
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

    if let exportedXMLPath = artifact.exportedXMLPath, fileExists(exportedXMLPath) {
      attachments.append(
        DiagnosticAttachment(
          id: ReportID(rawValue: "attachment:trace-export-xml:\(stable(exportedXMLPath))"),
          scope: scope,
          kind: .structuredData,
          title: "xctrace export XML",
          location: exportedXMLPath,
          contentType: "application/xml",
          metadata: metadata
        )
      )
    }

    if let tableOfContentsPath = artifact.tableOfContentsPath, fileExists(tableOfContentsPath) {
      attachments.append(
        DiagnosticAttachment(
          id: ReportID(rawValue: "attachment:trace-toc:\(stable(tableOfContentsPath))"),
          scope: scope,
          kind: .structuredData,
          title: "xctrace table of contents",
          location: tableOfContentsPath,
          contentType: "application/xml",
          metadata: metadata
        )
      )
    }

    return attachments
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

public struct XctraceCommandResult: Sendable, Equatable {
  public var terminationStatus: Int32
  public var standardOutput: String
  public var standardError: String

  public init(
    terminationStatus: Int32,
    standardOutput: String = "",
    standardError: String = ""
  ) {
    self.terminationStatus = terminationStatus
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}

public enum XctraceRecorderError: Error, CustomStringConvertible {
  case commandFailed(arguments: [String], result: XctraceCommandResult)

  public var description: String {
    switch self {
    case .commandFailed(let arguments, let result):
      return
        "xctrace command failed with status \(result.terminationStatus): \(arguments.joined(separator: " ")) \(result.standardError)"
    }
  }
}

public struct XctraceRecorder: Sendable {
  public var xcrunPath: String
  public var runner: @Sendable ([String]) async -> XctraceCommandResult

  public init(
    xcrunPath: String = "/usr/bin/xcrun",
    runner: (@Sendable ([String]) async -> XctraceCommandResult)? = nil
  ) {
    self.xcrunPath = xcrunPath
    self.runner =
      runner ?? { arguments in
        await XctraceRecorder.runProcess(xcrunPath: xcrunPath, arguments: arguments)
      }
  }

  public func record(
    executablePath: String,
    executableArguments: [String] = [],
    outputTracePath: String,
    template: String = "Time Profiler",
    targetStandardOutputPath: String? = nil,
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
    if let targetStandardOutputPath {
      arguments += ["--target-stdout", targetStandardOutputPath]
    }
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
        process.waitUntilExit()
        return XctraceCommandResult(
          terminationStatus: process.terminationStatus,
          standardOutput: String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
          ),
          standardError: String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
          )
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
