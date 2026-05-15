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
    let grouped = Dictionary(grouping: spans.compactMap { span -> (String, UInt64)? in
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

public enum TimelineCorrelationKeys {
  public static let suite = "benchmark.suite"
  public static let `case` = "benchmark.case"
  public static let iteration = "benchmark.iteration"
  public static let dimensionSize = "benchmark.dimension.size"
  public static let durationNanoseconds = "benchmark.duration.nanoseconds"
}

public enum TimelineCorrelator {
  public static func attribution(
    from timeline: Timeline,
    runID: ReportID,
    suiteName: String,
    caseName: String,
    size: Benchmark.Scale? = nil,
    iteration: Int
  ) -> TimelineAttribution {
    let suiteID = ReportIDFactory.suite(suiteName)
    let caseID = ReportIDFactory.benchmarkCase(suiteName: suiteName, caseName: caseName)
    let iterationID = ReportIDFactory.iteration(
      suiteName: suiteName,
      caseName: caseName,
      size: size,
      iteration: iteration
    )
    let sampleID = ReportIDFactory.sample(
      suiteName: suiteName,
      caseName: caseName,
      size: size,
      iteration: iteration
    )

    let directSpanIDs = Set(
      timeline.spans.filter { record in
        matches(
          record.attributes,
          suiteName: suiteName,
          caseName: caseName,
          size: size,
          iteration: iteration
        )
      }.map(\.id)
    )
    let spanByID = Dictionary(uniqueKeysWithValues: timeline.spans.map { ($0.id, $0) })
    let includedSpanIDs = Set(
      timeline.spans.filter { record in
        isSpan(record.id, descendantOfAny: directSpanIDs, spanByID: spanByID)
      }.map(\.id)
    )

    let spans = timeline.spans.filter { record in
      includedSpanIDs.contains(record.id)
    }.map(SpanAttribution.init)

    let events = timeline.events.filter { record in
      matches(record.attributes, suiteName: suiteName, caseName: caseName, size: size, iteration: iteration)
        || record.parentSpanID.map { includedSpanIDs.contains($0) } == true
    }.map(EventAttribution.init)

    return TimelineAttribution(
      scope: ReportScope(
        runID: runID,
        suiteID: suiteID,
        caseID: caseID,
        iterationID: iterationID,
        sampleID: sampleID
      ),
      spans: spans,
      events: events
    )
  }

  public static func attributions(
    from timeline: Timeline,
    runID: ReportID,
    results: [BenchmarkResult]
  ) -> [TimelineAttribution] {
    results.flatMap { result in
      result.measurement.rows.flatMap { row in
        row.samples.map { sample in
          attribution(
            from: timeline,
            runID: runID,
            suiteName: result.suiteName,
            caseName: result.caseName,
            size: row.size,
            iteration: sample.iteration
          )
        }
      }
    }
  }

  private static func matches(
    _ attributes: SpanAttributes,
    suiteName: String,
    caseName: String,
    size: Benchmark.Scale?,
    iteration: Int
  ) -> Bool {
    attributes.values[TimelineCorrelationKeys.suite] == .string(suiteName)
      && attributes.values[TimelineCorrelationKeys.case] == .string(caseName)
      && attributes.values[TimelineCorrelationKeys.iteration] == .int(iteration)
      && matchesDimension(attributes, size: size)
  }

  private static func matchesDimension(
    _ attributes: SpanAttributes,
    size: Benchmark.Scale?
  ) -> Bool {
    guard let size else {
      return attributes.values[TimelineCorrelationKeys.dimensionSize] == nil
        || attributes.values[TimelineCorrelationKeys.dimensionSize] == .string("none")
    }
    return attributes.values[TimelineCorrelationKeys.dimensionSize] == .int(size.rawValue)
  }

  private static func isSpan(
    _ id: Timeline.SpanID,
    descendantOfAny roots: Set<Timeline.SpanID>,
    spanByID: [Timeline.SpanID: Timeline.SpanRecord]
  ) -> Bool {
    if roots.contains(id) {
      return true
    }
    var current = spanByID[id]?.parentID
    while let candidate = current {
      if roots.contains(candidate) {
        return true
      }
      current = spanByID[candidate]?.parentID
    }
    return false
  }
}
