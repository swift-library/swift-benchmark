// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Testing

@testable import Instruments

@Suite("Freestanding Macros Runtime", .serialized)
struct FreestandingMacroRuntimeTests {
  @Test
  func spanMacroRecordsAndReturnsValue() {
    let recorder = InMemoryRecorder(stackKey: { 10 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = #span("BuildIndex", attributes: ["phase": "test"]) {
        42
      }

      let timeline = recorder.snapshot()
      #expect(value == 42)
      #expect(timeline.spans.count == 1)
      #expect(timeline.spans[0].name == "BuildIndex")
      #expect(timeline.spans[0].attributes.values["phase"] == .string("test"))
      #expect(timeline.spans[0].end != nil)
    }
  }

  @Test
  func spanMacroRecordsNestedSpans() {
    let recorder = InMemoryRecorder(stackKey: { 21 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = #span("Outer") {
        #span("Middle") {
          #span("Inner") {
            7
          }
        }
      }

      let timeline = recorder.snapshot()
      #expect(value == 7)
      #expect(timeline.spans.map(\.name) == ["Outer", "Middle", "Inner"])
      #expect(timeline.spans[0].parentID == nil)
      #expect(timeline.spans[1].parentID == timeline.spans[0].id)
      #expect(timeline.spans[2].parentID == timeline.spans[1].id)
      #expect(timeline.spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func spanMacroEndsWhenThrowing() {
    enum DummyError: Error, Equatable {
      case boom
    }

    let recorder = InMemoryRecorder(stackKey: { 11 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      do {
        _ = try #span("Throwing") {
          throw DummyError.boom
        }
        Issue.record("Expected #span to throw")
      } catch DummyError.boom {
        let timeline = recorder.snapshot()
        #expect(timeline.spans.count == 1)
        #expect(timeline.spans[0].end != nil)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  @Test
  func nestedSpanMacroEndsAllSpansWhenThrowing() {
    enum DummyError: Error, Equatable {
      case boom
    }

    let recorder = InMemoryRecorder(stackKey: { 22 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      do {
        _ = try #span("OuterThrowing") {
          try #span("InnerThrowing") {
            throw DummyError.boom
          }
        }
        Issue.record("Expected nested #span to throw")
      } catch DummyError.boom {
        let timeline = recorder.snapshot()
        #expect(timeline.spans.map(\.name) == ["OuterThrowing", "InnerThrowing"])
        #expect(timeline.spans[0].end != nil)
        #expect(timeline.spans[1].end != nil)
        #expect(timeline.spans[1].parentID == timeline.spans[0].id)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  @Test
  func optionalTryNestedSpanMacroEndsSpansWhenThrowing() {
    enum DummyError: Error, Equatable {
      case boom
    }
    func failingValue() throws -> Int {
      throw DummyError.boom
    }

    let recorder = InMemoryRecorder(stackKey: { 24 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = #span("OuterOptionalThrowing") {
        try? #span("InnerOptionalThrowing") {
          try failingValue()
        }
      }

      let timeline = recorder.snapshot()
      #expect(value == nil)
      #expect(timeline.spans.map(\.name) == ["OuterOptionalThrowing", "InnerOptionalThrowing"])
      #expect(timeline.spans[0].end != nil)
      #expect(timeline.spans[1].end != nil)
      #expect(timeline.spans[1].parentID == timeline.spans[0].id)
    }
  }

  @Test
  func forcedTryNestedSpanMacroReturnsValue() {
    let recorder = InMemoryRecorder(stackKey: { 25 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = #span("OuterForcedThrowing") {
        try! #span("InnerForcedThrowing") {
          try throwingDecoratedValue()
        }
      }

      let timeline = recorder.snapshot()
      #expect(value == 43)
      #expect(timeline.spans.map(\.name) == ["OuterForcedThrowing", "InnerForcedThrowing"])
      #expect(timeline.spans[1].parentID == timeline.spans[0].id)
      #expect(timeline.spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func asyncSpanMacroRecordsAndReturnsValue() async {
    let recorder = InMemoryRecorder(stackKey: { 12 })
    await InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = await #span("Async") {
        await asyncValue()
      }

      #expect(value == 5)
      #expect(recorder.snapshot().spans.map(\.name) == ["Async"])
    }
  }

  @Test
  func asyncSpanMacroRecordsNestedSpans() async {
    let recorder = InMemoryRecorder(stackKey: { 23 })
    await InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = await #span("AsyncOuter") {
        await #span("AsyncInner") {
          await asyncValue()
        }
      }

      let timeline = recorder.snapshot()
      #expect(value == 5)
      #expect(timeline.spans.map(\.name) == ["AsyncOuter", "AsyncInner"])
      #expect(timeline.spans[1].parentID == timeline.spans[0].id)
      #expect(timeline.spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func asyncThrowingSpanMacroRecordsNestedSpans() async throws {
    let recorder = InMemoryRecorder(stackKey: { 26 })
    try await InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = try await #span("AsyncThrowingOuter") {
        try await #span("AsyncThrowingInner") {
          try await asyncThrowingValue()
        }
      }

      let timeline = recorder.snapshot()
      #expect(value == 6)
      #expect(timeline.spans.map(\.name) == ["AsyncThrowingOuter", "AsyncThrowingInner"])
      #expect(timeline.spans[1].parentID == timeline.spans[0].id)
      #expect(timeline.spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func asyncThrowingSpanMacroRecordsAndReturnsValue() async throws {
    let recorder = InMemoryRecorder(stackKey: { 17 })
    try await InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = try await #span("AsyncThrowing") {
        try await asyncThrowingValue()
      }

      #expect(value == 6)
      #expect(recorder.snapshot().spans.map(\.name) == ["AsyncThrowing"])
    }
  }

  @Test
  func eventMacroRecordsPointEvent() {
    let recorder = InMemoryRecorder(stackKey: { 13 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      #event("CacheMiss", attributes: ["count": 1])

      let timeline = recorder.snapshot()
      #expect(timeline.events.count == 1)
      #expect(timeline.events[0].name == "CacheMiss")
      #expect(timeline.spans.isEmpty)
    }
  }

  private func asyncValue() async -> Int {
    5
  }

  private func asyncThrowingValue() async throws -> Int {
    6
  }
}
