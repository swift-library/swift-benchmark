import Testing

@testable import Instruments

@Span("decorated")
private func decoratedSpanFunction() -> Int {
  41 + 1
}

@Span("decoratedThrowing")
private func decoratedThrowingSpanFunction() throws -> Int {
  try throwingDecoratedValue()
}

@Instrumented
private func decoratedInstrumentedFunction() -> String {
  "ok"
}

@Instrumented
private func decoratedAsyncInstrumentedFunction() async throws -> Int {
  try await asyncDecoratedValue()
}

@InstrumentedMembers
private struct DecoratedStore {
  func load() -> Int {
    7
  }

  @Span("manual")
  func manual() -> Int {
    8
  }

  var computed: Int {
    9
  }
}

private func throwingDecoratedValue() throws -> Int {
  43
}

private func asyncDecoratedValue() async throws -> Int {
  await Task.yield()
  return 12
}

@Suite("Instruments Macros Runtime", .serialized)
struct InstrumentsMacroRuntimeTests {
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

  @Test
  func attachedSpanMacroRecordsFunctionBody() {
    let recorder = InMemoryRecorder(stackKey: { 14 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      #expect(decoratedSpanFunction() == 42)
      #expect(recorder.snapshot().spans.map(\.name) == ["decorated"])
    }
  }

  @Test
  func attachedSpanMacroPreservesThrowingFunction() throws {
    let recorder = InMemoryRecorder(stackKey: { 18 })
    try InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = try decoratedThrowingSpanFunction()
      #expect(value == 43)
      #expect(recorder.snapshot().spans.map(\.name) == ["decoratedThrowing"])
    }
  }

  @Test
  func functionLevelInstrumentedMacroRecordsFunctionBody() {
    let recorder = InMemoryRecorder(stackKey: { 15 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      #expect(decoratedInstrumentedFunction() == "ok")
      #expect(recorder.snapshot().spans.map(\.name) == ["decoratedInstrumentedFunction"])
    }
  }

  @Test
  func functionLevelInstrumentedMacroPreservesAsyncThrowingFunction() async throws {
    let recorder = InMemoryRecorder(stackKey: { 19 })
    try await InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = try await decoratedAsyncInstrumentedFunction()
      #expect(value == 12)
      #expect(recorder.snapshot().spans.map(\.name) == ["decoratedAsyncInstrumentedFunction"])
    }
  }

  @Test
  func instrumentedMembersMacroRecordsEligibleMethodsOnly() {
    let recorder = InMemoryRecorder(stackKey: { 20 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let store = DecoratedStore()
      #expect(store.load() == 7)
      #expect(store.manual() == 8)
      #expect(store.computed == 9)

      #expect(recorder.snapshot().spans.map(\.name) == ["DecoratedStore.load", "manual"])
    }
  }

  private func asyncValue() async -> Int {
    5
  }

  private func asyncThrowingValue() async throws -> Int {
    6
  }
}
