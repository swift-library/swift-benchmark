// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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

func throwingDecoratedValue() throws -> Int {
  43
}

private func asyncDecoratedValue() async throws -> Int {
  await Task.yield()
  return 12
}

@Suite("Attached Macros Runtime", .serialized)
struct AttachedMacroRuntimeTests {
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
      #expect(
        recorder.snapshot().spans.map(\.name) == ["DecoratedInstrumentedInitializer.init(_:mode:)"])
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
}
