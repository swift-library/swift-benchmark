// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

public struct SourceLocationReport: Sendable, Equatable, Codable {
  public var fileID: String
  public var filePath: String
  public var line: Int
  public var column: Int

  public init(fileID: String, filePath: String, line: Int, column: Int) {
    self.fileID = fileID
    self.filePath = filePath
    self.line = line
    self.column = column
  }
}

public struct RunMetadata: Sendable, Equatable, Codable {
  public var id: ReportID
  public var swiftVersion: String
  public var packageIdentity: String
  public var gitCommit: String?
  public var platform: String
  public var architecture: String
  public var osVersion: String
  public var generatedAt: String
  public var buildConfiguration: String
  public var device: String?

  public init(
    id: ReportID,
    swiftVersion: String,
    packageIdentity: String,
    gitCommit: String? = nil,
    platform: String,
    architecture: String,
    osVersion: String,
    generatedAt: String,
    buildConfiguration: String,
    device: String? = nil
  ) {
    self.id = id
    self.swiftVersion = swiftVersion
    self.packageIdentity = packageIdentity
    self.gitCommit = gitCommit
    self.platform = platform
    self.architecture = architecture
    self.osVersion = osVersion
    self.generatedAt = generatedAt
    self.buildConfiguration = buildConfiguration
    self.device = device
  }

  public static func local(
    id: ReportID,
    packageIdentity: String = "swift-benchmark",
    gitCommit: String? = nil,
    generatedAt: String = ISO8601DateFormatter().string(from: Date()),
    buildConfiguration: String? = nil
  ) -> RunMetadata {
    RunMetadata(
      id: id,
      swiftVersion: "unknown",
      packageIdentity: packageIdentity,
      gitCommit: gitCommit,
      platform: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: SystemArchitecture.current,
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      generatedAt: generatedAt,
      buildConfiguration: buildConfiguration
        ?? ProcessInfo.processInfo.environment["SWIFT_BENCHMARK_BUILD_CONFIGURATION"]
        ?? "debug",
      device: nil
    )
  }
}

enum SystemArchitecture {
  static var current: String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #elseif arch(arm)
      "arm"
    #elseif arch(i386)
      "i386"
    #else
      "unknown"
    #endif
  }
}

public struct BenchmarkConfigurationReport: Sendable, Equatable, Codable {
  public var warmup: String
  public var iterations: String

  public init(warmup: String, iterations: String) {
    self.warmup = warmup
    self.iterations = iterations
  }
}

public struct SampleReport: Sendable, Equatable, Codable {
  public var id: ReportID
  public var iterationID: ReportID
  public var iteration: Int
  public var durationNanoseconds: UInt64

  public init(
    id: ReportID,
    iterationID: ReportID,
    iteration: Int,
    durationNanoseconds: UInt64
  ) {
    self.id = id
    self.iterationID = iterationID
    self.iteration = iteration
    self.durationNanoseconds = durationNanoseconds
  }
}
