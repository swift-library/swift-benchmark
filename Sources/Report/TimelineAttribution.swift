// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Instruments

public struct ReportAttributeValue: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    case string
    case int
    case double
    case bool
  }

  public var kind: Kind
  public var stringValue: String?
  public var intValue: Int?
  public var doubleValue: Double?
  public var boolValue: Bool?

  public init(_ value: SpanAttributeValue) {
    switch value {
    case .string(let string):
      self.kind = .string
      self.stringValue = string
      self.intValue = nil
      self.doubleValue = nil
      self.boolValue = nil
    case .int(let int):
      self.kind = .int
      self.stringValue = nil
      self.intValue = int
      self.doubleValue = nil
      self.boolValue = nil
    case .double(let double):
      self.kind = .double
      self.stringValue = nil
      self.intValue = nil
      self.doubleValue = double
      self.boolValue = nil
    case .bool(let bool):
      self.kind = .bool
      self.stringValue = nil
      self.intValue = nil
      self.doubleValue = nil
      self.boolValue = bool
    }
  }
}

public struct SpanAttribution: Sendable, Equatable, Codable {
  public var id: ReportID
  public var parentID: ReportID?
  public var name: String
  public var startNanoseconds: UInt64
  public var endNanoseconds: UInt64?
  public var durationNanoseconds: UInt64?
  public var attributes: [String: ReportAttributeValue]

  public init(record: Timeline.SpanRecord) {
    self.id = ReportID(rawValue: "span:\(record.id.rawValue)")
    self.parentID = record.parentID.map { ReportID(rawValue: "span:\($0.rawValue)") }
    self.name = record.name
    self.startNanoseconds = record.start
    self.endNanoseconds = record.end
    self.durationNanoseconds = record.duration
    self.attributes = record.attributes.values.mapValues(ReportAttributeValue.init)
  }
}

public struct EventAttribution: Sendable, Equatable, Codable {
  public var id: ReportID
  public var parentSpanID: ReportID?
  public var name: String
  public var timestampNanoseconds: UInt64
  public var attributes: [String: ReportAttributeValue]

  public init(record: Timeline.EventRecord) {
    self.id = ReportID(rawValue: "event:\(record.id.rawValue)")
    self.parentSpanID = record.parentSpanID.map { ReportID(rawValue: "span:\($0.rawValue)") }
    self.name = record.name
    self.timestampNanoseconds = record.timestamp
    self.attributes = record.attributes.values.mapValues(ReportAttributeValue.init)
  }
}

public struct TimelineAttribution: Sendable, Equatable, Codable {
  public var scope: ReportScope
  public var spans: [SpanAttribution]
  public var events: [EventAttribution]
  public var spanSummaries: [SpanTimingSummary]

  public init(
    scope: ReportScope,
    spans: [SpanAttribution],
    events: [EventAttribution],
    spanSummaries: [SpanTimingSummary]? = nil
  ) {
    self.scope = scope
    self.spans = spans
    self.events = events
    self.spanSummaries = spanSummaries ?? SpanTimingSummary.summarize(spans: spans)
  }
}

public struct SpanTimingSummary: Sendable, Equatable, Codable {
  public var name: String
  public var count: Int
  public var totalNanoseconds: UInt64
  public var minNanoseconds: UInt64
  public var maxNanoseconds: UInt64
  public var meanNanoseconds: Double

  public init(
    name: String,
    count: Int,
    totalNanoseconds: UInt64,
    minNanoseconds: UInt64,
    maxNanoseconds: UInt64,
    meanNanoseconds: Double
  ) {
    self.name = name
    self.count = count
    self.totalNanoseconds = totalNanoseconds
    self.minNanoseconds = minNanoseconds
    self.maxNanoseconds = maxNanoseconds
    self.meanNanoseconds = meanNanoseconds
  }

  static func summarize(spans: [SpanAttribution]) -> [SpanTimingSummary] {
    let grouped = Dictionary(
      grouping: spans.compactMap { span -> (String, UInt64)? in
        guard let duration = span.durationNanoseconds else {
          return nil
        }
        return (span.name, duration)
      }, by: \.0)

    return grouped.keys.sorted().map { name in
      let durations = (grouped[name] ?? []).map(\.1)
      let total = durations.reduce(0, +)
      return SpanTimingSummary(
        name: name,
        count: durations.count,
        totalNanoseconds: total,
        minNanoseconds: durations.min() ?? 0,
        maxNanoseconds: durations.max() ?? 0,
        meanNanoseconds: durations.isEmpty ? 0 : Double(total) / Double(durations.count)
      )
    }
  }
}
