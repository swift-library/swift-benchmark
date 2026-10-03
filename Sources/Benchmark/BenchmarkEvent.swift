// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

public protocol BenchmarkEventRecorder: Sendable {
  func record(_ record: Benchmark.Event.Stream.Record) async
}

extension Benchmark {
  public enum Event: Sendable {}
}

extension Benchmark.Event {
  public enum Kind: String, Sendable, Codable, Equatable, CaseIterable {
    case discoveryStarted
    case discoveryEnded
    case planStarted
    case planEnded
    case suiteStarted
    case suiteEnded
    case caseStarted
    case caseEnded
    case dimensionRowStarted
    case dimensionRowEnded
    case warmupStarted
    case warmupEnded
    case iterationStarted
    case iterationEnded
    case sampleRecorded
    case skipped
    case issueRecorded
    case diagnosticRecorded
    case attachmentRecorded
    case runEnded
  }

  public struct Context: Sendable, Codable, Equatable {
    public var suiteName: String?
    public var caseName: String?
    public var stepID: String?
    public var size: Benchmark.Scale?
    public var argumentRowID: String?
    public var arguments: [Benchmark.ArgumentValue]
    public var iteration: Int?
    public var phase: String?
    public var durationNanoseconds: UInt64?
    public var tags: [String]
    public var sourceLocation: BenchmarkSourceLocation?
    public var configurationWarmup: String?
    public var configurationIterations: String?
    public var message: String?

    public init(
      suiteName: String? = nil,
      caseName: String? = nil,
      stepID: String? = nil,
      size: Benchmark.Scale? = nil,
      argumentRowID: String? = nil,
      arguments: [Benchmark.ArgumentValue] = [],
      iteration: Int? = nil,
      phase: String? = nil,
      durationNanoseconds: UInt64? = nil,
      tags: [String] = [],
      sourceLocation: BenchmarkSourceLocation? = nil,
      configurationWarmup: String? = nil,
      configurationIterations: String? = nil,
      message: String? = nil
    ) {
      self.suiteName = suiteName
      self.caseName = caseName
      self.stepID = stepID
      self.size = size
      self.argumentRowID = argumentRowID
      self.arguments = arguments
      self.iteration = iteration
      self.phase = phase
      self.durationNanoseconds = durationNanoseconds
      self.tags = tags
      self.sourceLocation = sourceLocation
      self.configurationWarmup = configurationWarmup
      self.configurationIterations = configurationIterations
      self.message = message
    }

    init(
      step: BenchmarkRunner.Plan.Step,
      iteration: Int? = nil,
      phase: BenchmarkPhase? = nil,
      durationNanoseconds: UInt64? = nil,
      message: String? = nil
    ) {
      self.init(
        suiteName: step.suiteName,
        caseName: step.caseName,
        stepID: step.id,
        size: step.size,
        argumentRowID: step.argumentRow?.id,
        arguments: step.arguments,
        iteration: iteration,
        phase: phase.map(String.init(describing:)),
        durationNanoseconds: durationNanoseconds,
        tags: step.tags,
        sourceLocation: step.benchmarkCase.sourceLocation,
        configurationWarmup: String(describing: step.configuration.warmup),
        configurationIterations: String(describing: step.configuration.iterations),
        message: message
      )
    }
  }

  public enum Stream: Sendable {}
}

extension Benchmark.Event.Stream {
  public struct Record: Sendable, Codable, Equatable {
    public var sequence: Int
    public var kind: Benchmark.Event.Kind
    public var context: Benchmark.Event.Context

    public init(
      sequence: Int = 0,
      kind: Benchmark.Event.Kind,
      context: Benchmark.Event.Context
    ) {
      self.sequence = sequence
      self.kind = kind
      self.context = context
    }
  }
}

extension Benchmark.Event {
  public actor InMemoryRecorder: BenchmarkEventRecorder {
    private var storage: [Benchmark.Event.Stream.Record] = []
    private var nextSequence = 0

    public init() {}

    public func record(_ record: Benchmark.Event.Stream.Record) {
      storage.append(record.withSequence(nextSequence))
      nextSequence += 1
    }

    public func snapshot() -> [Benchmark.Event.Stream.Record] {
      storage
    }
  }

  public struct ConsoleRecorder: BenchmarkEventRecorder {
    public init() {}

    public func record(_ record: Benchmark.Event.Stream.Record) async {
      let suite = record.context.suiteName ?? "-"
      let benchmarkCase = record.context.caseName ?? "-"
      print("[benchmark] \(record.kind.rawValue) \(suite).\(benchmarkCase)")
    }
  }

  public actor JSONLinesRecorder: BenchmarkEventRecorder {
    private var storage: [String] = []
    private var nextSequence = 0
    private let encoder: JSONEncoder

    public init() {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      self.encoder = encoder
    }

    public func record(_ record: Benchmark.Event.Stream.Record) {
      let sequenced = record.withSequence(nextSequence)
      nextSequence += 1
      if let data = try? encoder.encode(sequenced) {
        storage.append(String(decoding: data, as: UTF8.self))
      }
    }

    public func lines() -> [String] {
      storage
    }
  }
}

extension Benchmark.Event.Stream.Record {
  fileprivate func withSequence(_ sequence: Int) -> Benchmark.Event.Stream.Record {
    Benchmark.Event.Stream.Record(sequence: sequence, kind: kind, context: context)
  }
}
