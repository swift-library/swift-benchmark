// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Report
import Testing

@Suite("Timeline Correlation")
struct TimelineCorrelationTests {
  @Test
  func timelineCorrelatorIncludesChildSpansAndEventsUnderCorrelatedParent() throws {
    let metadata = RunMetadata.fixture()
    let attribution = TimelineCorrelator.attribution(
      from: makeNestedTimeline(),
      runID: metadata.id,
      suiteName: "Parser",
      caseName: "ParseDocument",
      iteration: 1
    )

    #expect(attribution.spans.map(\.name) == ["IterationRoot", "ParseAST"])
    #expect(attribution.events.map(\.name) == ["CacheMiss"])
    #expect(attribution.spans[1].parentID == attribution.spans[0].id)
    #expect(attribution.events.first?.parentSpanID == attribution.spans[1].id)
    #expect(attribution.spanSummaries.map(\.name) == ["IterationRoot", "ParseAST"])
  }
}
