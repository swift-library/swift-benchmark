// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
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

  /// Metadata for a run in the current process.
  ///
  /// Without an explicit `buildConfiguration`, the configuration is the one
  /// this module was compiled in, which is the configuration of the build
  /// that produced the benchmark code. The Swift version is known only to
  /// the release it belongs to; the package workflow replaces it with the
  /// exact version of the compiler that built the host.
  public static func local(
    id: ReportID,
    packageIdentity: String = "swift-benchmark",
    gitCommit: String? = nil,
    generatedAt: String = ISO8601DateFormatter().string(from: Date()),
    buildConfiguration: String? = nil
  ) -> RunMetadata {
    RunMetadata(
      id: id,
      swiftVersion: SwiftCompilerVersion.current,
      packageIdentity: packageIdentity,
      gitCommit: gitCommit,
      platform: OperatingSystemName.current,
      architecture: SystemArchitecture.current,
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      generatedAt: generatedAt,
      buildConfiguration: buildConfiguration ?? BuildConfigurationName.current,
      device: MachineModel.current
    )
  }
}

enum SwiftCompilerVersion {
  /// The compiler release this module was compiled with, as precisely as
  /// conditional compilation can tell.
  static var current: String {
    #if compiler(>=6.5)
      "6.5 or later"
    #elseif compiler(>=6.4)
      "6.4"
    #else
      "6.3"
    #endif
  }
}

enum BuildConfigurationName {
  /// The SwiftPM configuration this library was compiled in; SwiftPM defines
  /// `DEBUG` only for debug builds.
  static var current: String {
    #if DEBUG
      "debug"
    #else
      "release"
    #endif
  }
}

enum OperatingSystemName {
  static var current: String {
    #if os(macOS)
      "macOS"
    #elseif os(iOS)
      "iOS"
    #elseif os(tvOS)
      "tvOS"
    #elseif os(watchOS)
      "watchOS"
    #elseif os(visionOS)
      "visionOS"
    #elseif os(Linux)
      "Linux"
    #elseif os(Windows)
      "Windows"
    #else
      "unknown"
    #endif
  }
}

enum MachineModel {
  /// The hardware model identifier, such as `Mac15,8`, where the platform reports one.
  static var current: String? {
    #if canImport(Darwin)
      var size = 0
      guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
        return nil
      }
      var buffer = [CChar](repeating: 0, count: size)
      guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
        return nil
      }
      return String(
        decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    #else
      return nil
    #endif
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
  /// The case's batching policy, described as text.
  public var batching: String

  /// Records a case's configuration as text.
  public init(warmup: String, iterations: String, batching: String) {
    self.warmup = warmup
    self.iterations = iterations
    self.batching = batching
  }
}

/// One recorded sample: per-call values keyed by metric name.
public struct SampleReport: Sendable, Equatable, Codable {
  public var id: ReportID
  public var iterationID: ReportID
  public var iteration: Int
  /// Calls the sample measured.
  public var batchSize: Int
  /// Per-call values keyed by metric name.
  public var values: [String: Double]

  public init(
    id: ReportID,
    iterationID: ReportID,
    iteration: Int,
    batchSize: Int = 1,
    values: [String: Double]
  ) {
    self.id = id
    self.iterationID = iterationID
    self.iteration = iteration
    self.batchSize = batchSize
    self.values = values
  }

  /// The per-call value of `metric`, or `nil` when the sample did not measure it.
  public func value(for metric: Benchmark.Metric) -> Double? {
    values[metric.name]
  }
}
