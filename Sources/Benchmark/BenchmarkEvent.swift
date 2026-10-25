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
  /// What happened: a run's plan starts and ends around its steps, and each
  /// step's case and row bracket its warmup, iterations and samples.
  public enum Kind: String, Sendable, Codable, Equatable, CaseIterable {
    case planStarted
    case planEnded
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
    /// Calls measured by the recorded sample.
    public var batchSize: Int?
    /// Per-call sample values keyed by metric name.
    public var values: [String: Double]
    /// Descriptions of the metrics named in `values`.
    public var metrics: [Benchmark.Metric]
    public var tags: [String]
    public var sourceLocation: BenchmarkSourceLocation?
    public var configurationWarmup: String?
    public var configurationIterations: String?
    /// The case's batching policy, described as text.
    public var configurationBatching: String?
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
      batchSize: Int? = nil,
      values: [String: Double] = [:],
      metrics: [Benchmark.Metric] = [],
      tags: [String] = [],
      sourceLocation: BenchmarkSourceLocation? = nil,
      configurationWarmup: String? = nil,
      configurationIterations: String? = nil,
      configurationBatching: String? = nil,
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
      self.batchSize = batchSize
      self.values = values
      self.metrics = metrics
      self.tags = tags
      self.sourceLocation = sourceLocation
      self.configurationWarmup = configurationWarmup
      self.configurationIterations = configurationIterations
      self.configurationBatching = configurationBatching
      self.message = message
    }

    init(
      step: BenchmarkRunner.Plan.Step,
      iteration: Int? = nil,
      phase: BenchmarkPhase? = nil,
      sample: Sample? = nil,
      message: String? = nil
    ) {
      let metrics = sample.map { $0.values.keys.sorted { $0.name < $1.name } } ?? []
      self.init(
        suiteName: step.suiteName,
        caseName: step.caseName,
        stepID: step.id,
        size: step.size,
        argumentRowID: step.argumentRow?.id,
        arguments: step.arguments,
        iteration: iteration,
        phase: phase.map(String.init(describing:)),
        batchSize: sample?.batchSize,
        values: Dictionary(
          uniqueKeysWithValues: (sample?.values ?? [:]).map { ($0.key.name, $0.value) }),
        metrics: metrics,
        tags: step.tags,
        sourceLocation: step.benchmarkCase.sourceLocation,
        configurationWarmup: String(describing: step.configuration.warmup),
        configurationIterations: String(describing: step.configuration.iterations),
        configurationBatching: String(describing: step.configuration.batching),
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
