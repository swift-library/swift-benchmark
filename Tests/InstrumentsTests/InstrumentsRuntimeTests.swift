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
  func instrumentsCurrentCanBeSetAndReset() {
    let recorder = InMemoryRecorder(stackKey: { 3 })
    InstrumentsCurrentIsolation.withRecorder(recorder) {
      Instruments.current.recordEvent("current", attributes: [:])
      #expect(recorder.snapshot().events.map(\.name) == ["current"])
    }
  }
}
