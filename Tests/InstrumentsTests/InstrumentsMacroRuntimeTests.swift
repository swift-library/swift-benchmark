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

private struct DecoratedExplicitInitializer {
  let value: Int

  @Span("DecoratedExplicitInitializer.init")
  init(value: Int) {
    self.value = value
  }
}

private struct DecoratedInstrumentedInitializer {
  let value: Int

  @Instrumented
  init(_ value: Int, mode: String) {
    self.value = value + mode.count
  }
}

private enum DecoratedInitializerError: Error, Equatable {
  case boom
}

private struct DecoratedThrowingInitializer {
  let value: Int

  @Span("DecoratedThrowingInitializer.init")
  init(shouldThrow: Bool) throws {
    self.value = 0
    if shouldThrow {
      throw DecoratedInitializerError.boom
    }
  }
}

private struct DecoratedFailableInitializer {
  let value: Int

  @Span("DecoratedFailableInitializer.init")
  init?(_ value: Int) {
    if value < 0 {
      return nil
    }
    self.value = value
  }
}

@InstrumentedMembers
private struct DecoratedInitializerStore {
  let value: Int

  init(path: String) {
    self.value = path.count
  }

  @Span("manualInitializer")
  init(manual: Int) {
    self.value = manual
  }

  @Instrumented
  init(alias: Int) {
    self.value = alias
  }

  func load() -> Int {
    value
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

  @Test
  func attachedSpanMacroRecordsInitializerBody() {
    let recorder = InMemoryRecorder(stackKey: { 27 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = DecoratedExplicitInitializer(value: 9)

      #expect(value.value == 9)
      #expect(recorder.snapshot().spans.map(\.name) == ["DecoratedExplicitInitializer.init"])
      #expect(recorder.snapshot().spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func instrumentedMacroRecordsInitializerBodyWithDefaultName() {
    let recorder = InMemoryRecorder(stackKey: { 28 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = DecoratedInstrumentedInitializer(8, mode: "abc")

      #expect(value.value == 11)
      #expect(recorder.snapshot().spans.map(\.name) == ["DecoratedInstrumentedInitializer.init(_:mode:)"])
      #expect(recorder.snapshot().spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func attachedSpanMacroEndsInitializerSpanWhenThrowing() {
    let recorder = InMemoryRecorder(stackKey: { 29 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      do {
        _ = try DecoratedThrowingInitializer(shouldThrow: true)
        Issue.record("Expected initializer to throw")
      } catch DecoratedInitializerError.boom {
        let timeline = recorder.snapshot()
        #expect(timeline.spans.map(\.name) == ["DecoratedThrowingInitializer.init"])
        #expect(timeline.spans.allSatisfy { $0.end != nil })
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  @Test
  func attachedSpanMacroEndsInitializerSpanWhenReturningNil() {
    let recorder = InMemoryRecorder(stackKey: { 30 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let value = DecoratedFailableInitializer(-1)

      #expect(value == nil)
      #expect(recorder.snapshot().spans.map(\.name) == ["DecoratedFailableInitializer.init"])
      #expect(recorder.snapshot().spans.allSatisfy { $0.end != nil })
    }
  }

  @Test
  func instrumentedMembersMacroRecordsInitializerBodies() {
    let recorder = InMemoryRecorder(stackKey: { 31 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      let path = DecoratedInitializerStore(path: "abc")
      let manual = DecoratedInitializerStore(manual: 4)
      let alias = DecoratedInitializerStore(alias: 5)

      #expect(path.load() == 3)
      #expect(manual.load() == 4)
      #expect(alias.load() == 5)
      #expect(
        recorder.snapshot().spans.map(\.name) == [
          "DecoratedInitializerStore.init(path:)",
          "manualInitializer",
          "DecoratedInitializerStore.init(alias:)",
          "DecoratedInitializerStore.load",
          "DecoratedInitializerStore.load",
          "DecoratedInitializerStore.load",
        ]
      )
      #expect(recorder.snapshot().spans.allSatisfy { $0.end != nil })
    }
  }

  private func asyncValue() async -> Int {
    5
  }

  private func asyncThrowingValue() async throws -> Int {
    6
  }
}
