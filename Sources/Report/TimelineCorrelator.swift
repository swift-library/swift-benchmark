// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Instruments

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
      matches(
        record.attributes, suiteName: suiteName, caseName: caseName, size: size,
        iteration: iteration)
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
