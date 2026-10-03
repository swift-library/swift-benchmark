// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Testing

@testable import Instruments

@Suite("Instruments Runtime", .serialized)
struct InstrumentsRuntimeTests {
  @Test
  func inMemoryRecorderRecordsNestedSpansAndEvents() {
    final class TestClock: @unchecked Sendable {
      var tick: UInt64 = 10

      func next() -> UInt64 {
        defer {
          tick += 10
        }
        return tick
      }
    }

    let clock = TestClock()
    let recorder = InMemoryRecorder(
      clock: { clock.next() },
      stackKey: { 1 }
    )

    let outer = recorder.beginSpan("outer", attributes: ["component": "test"])
    let inner = recorder.beginSpan("inner", attributes: ["index": 1])
    recorder.recordEvent("point", attributes: ["hit": true])
    recorder.endSpan(inner)
    recorder.endSpan(outer)

    let timeline = recorder.snapshot()
    #expect(timeline.spans.count == 2)
    #expect(timeline.events.count == 1)
    #expect(timeline.spans[0].name == "outer")
    #expect(timeline.spans[1].name == "inner")
    #expect(timeline.spans[1].parentID == timeline.spans[0].id)
    #expect(timeline.events[0].parentSpanID == timeline.spans[1].id)
    #expect(timeline.spans.allSatisfy { $0.end != nil })
  }

  @Test
  func recorderConvenienceSpanEndsWhenOperationThrows() {
    enum DummyError: Error, Equatable {
      case boom
    }

    let recorder = InMemoryRecorder(stackKey: { 2 })

    do {
      _ = try recorder.span("throwing") {
        throw DummyError.boom
      }
      Issue.record("Expected throwing span to throw")
    } catch DummyError.boom {
      let timeline = recorder.snapshot()
      #expect(timeline.spans.count == 1)
      #expect(timeline.spans[0].end != nil)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func compositeRecorderFansOutSpansAndEvents() {
    let first = InMemoryRecorder(stackKey: { 4 })
    let second = InMemoryRecorder(stackKey: { 4 })
    let recorder = CompositeRecorder([first, second])

    let outer = recorder.beginSpan("outer", attributes: ["component": "test"])
    let inner = recorder.beginSpan("inner", attributes: ["index": 1])
    recorder.recordEvent("point", attributes: ["hit": true])
    recorder.endSpan(inner)
    recorder.endSpan(outer)

    let firstTimeline = first.snapshot()
    let secondTimeline = second.snapshot()

    #expect(firstTimeline.spans.map(\.name) == ["outer", "inner"])
    #expect(secondTimeline.spans.map(\.name) == ["outer", "inner"])
    #expect(firstTimeline.events.map(\.name) == ["point"])
    #expect(secondTimeline.events.map(\.name) == ["point"])
    #expect(firstTimeline.spans[1].parentID == firstTimeline.spans[0].id)
    #expect(secondTimeline.spans[1].parentID == secondTimeline.spans[0].id)
    #expect(firstTimeline.events[0].parentSpanID == firstTimeline.spans[1].id)
    #expect(secondTimeline.events[0].parentSpanID == secondTimeline.spans[1].id)
  }

  @Test
  func instrumentsCurrentCanBeSetAndReset() {
    let recorder = InMemoryRecorder(stackKey: { 3 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      Instruments.current.recordEvent("current", attributes: [:])
      #expect(recorder.snapshot().events.map(\.name) == ["current"])
    }
  }

  @Test
  func scopedCurrentRecorderRestoresAfterThrowingOperation() {
    enum DummyError: Error, Equatable {
      case boom
    }

    let outer = InMemoryRecorder(stackKey: { 5 })
    let inner = InMemoryRecorder(stackKey: { 5 })

    Instruments.withCurrentRecorder(outer) {
      do {
        try Instruments.withCurrentRecorder(inner) {
          Instruments.current.recordEvent("inner", attributes: [:])
          throw DummyError.boom
        }
        Issue.record("Expected scoped recorder operation to throw")
      } catch DummyError.boom {
        Instruments.current.recordEvent("outer", attributes: [:])
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }

    #expect(inner.snapshot().events.map(\.name) == ["inner"])
    #expect(outer.snapshot().events.map(\.name) == ["outer"])
  }

  @Test
  func scopedCurrentRecorderRestoresAfterAsyncThrowingOperation() async {
    enum DummyError: Error, Equatable {
      case boom
    }

    let outer = InMemoryRecorder(stackKey: { 6 })
    let inner = InMemoryRecorder(stackKey: { 6 })

    await Instruments.withCurrentRecorder(outer) {
      do {
        try await Instruments.withCurrentRecorder(inner) {
          await Task.yield()
          Instruments.current.recordEvent("async-inner", attributes: [:])
          throw DummyError.boom
        }
        Issue.record("Expected scoped recorder async operation to throw")
      } catch DummyError.boom {
        Instruments.current.recordEvent("async-outer", attributes: [:])
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }

    #expect(inner.snapshot().events.map(\.name) == ["async-inner"])
    #expect(outer.snapshot().events.map(\.name) == ["async-outer"])
  }
}
