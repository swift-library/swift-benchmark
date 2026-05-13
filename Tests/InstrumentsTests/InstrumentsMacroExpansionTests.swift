#if canImport(SwiftSyntaxMacrosTestSupport)
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import InstrumentsMacro

@Suite("Instruments Macro Expansion")
struct InstrumentsMacroExpansionTests {
  private let macros: [String: Macro.Type] = [
    "span": SpanMacro.self,
    "event": EventMacro.self,
    "Span": SpanAttributeMacro.self,
    "Instrumented": InstrumentedBodyMacro.self,
    "InstrumentedMembers": InstrumentedMembersMacro.self,
  ]

  @Test
  func spanMacroExpandsToRuntimeRecorderCalls() {
    assertMacroExpansion(
      """
      let value = #span("Operation") {
        1
      }
      """,
      expandedSource: """
      let value = {
        let __instrumentsRecorder = Instruments.current
        let __instrumentsToken = __instrumentsRecorder.beginSpan("Operation", attributes: .empty)
        defer {
          __instrumentsRecorder.endSpan(__instrumentsToken)
        }
        return {
          1
        }()
      }()
      """,
      macros: macros
    )
  }

  @Test
  func eventMacroExpandsToRuntimeRecorderCall() {
    assertMacroExpansion(
      """
      #event("CacheMiss")
      """,
      expandedSource: """
      Instruments.current.recordEvent("CacheMiss", attributes: .empty)
      """,
      macros: macros
    )
  }

  @Test
  func instrumentedMembersMacroAddsSpanAttributesToFunctionsOnly() {
    assertMacroExpansion(
      """
      @InstrumentedMembers
      struct Store {
        func load() -> Int {
          1
        }

        var count: Int {
          2
        }
      }
      """,
      expandedSource: """
      struct Store {
        @Span("Store.load")
        func load() -> Int {
          1
        }

        var count: Int {
          2
        }
      }
      """,
      macros: macros
    )
  }
}
#endif
