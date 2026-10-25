// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import MacroTesting
import SwiftSyntaxMacros
import Testing

@testable import InstrumentsMacro

@Suite("Freestanding Macro Expansion")
struct FreestandingMacroExpansionTests {
  private let macros: [String: Macro.Type] = [
    "span": SpanMacro.self,
    "event": EventMacro.self,
    "Span": SpanAttributeMacro.self,
    "Instrumented": InstrumentedBodyMacro.self,
    "InstrumentedMembers": InstrumentedMembersMacro.self,
  ]

  @Test
  func expansionMismatchIsReportedToSwiftTesting() {
    withKnownIssue("A mismatched expansion must produce a Swift Testing issue.") {
      assertMacroExpansion(
        "#event(\"Operation\")",
        expandedSource: "unexpectedExpansion()",
        macros: macros
      )
    }
  }

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
  func spanMacroLowersNestedSpansRecursively() {
    assertMacroExpansion(
      """
      let value = #span("Outer") {
        #span("Middle") {
          #span("Inner") {
            1
          }
        }
      }
      """,
      expandedSource: """
        let value = {
          let __instrumentsRecorder = Instruments.current
          let __instrumentsToken = __instrumentsRecorder.beginSpan("Outer", attributes: .empty)
          defer {
            __instrumentsRecorder.endSpan(__instrumentsToken)
          }
          return {
            {
              let __instrumentsRecorder = Instruments.current
              let __instrumentsToken = __instrumentsRecorder.beginSpan("Middle", attributes: .empty)
              defer {
                __instrumentsRecorder.endSpan(__instrumentsToken)
              }
              return {
                {
                  let __instrumentsRecorder = Instruments.current
                  let __instrumentsToken = __instrumentsRecorder.beginSpan("Inner", attributes: .empty)
                  defer {
                    __instrumentsRecorder.endSpan(__instrumentsToken)
                  }
                  return {
                      1
                    }()
                }()
              }()
            }()
          }()
        }()
        """,
      macros: macros
    )
  }

  @Test
  func spanMacroLowersNestedEvents() {
    assertMacroExpansion(
      """
      let value = #span("Outer") {
        #event("Inside")
        return 1
      }
      """,
      expandedSource: """
        let value = {
          let __instrumentsRecorder = Instruments.current
          let __instrumentsToken = __instrumentsRecorder.beginSpan("Outer", attributes: .empty)
          defer {
            __instrumentsRecorder.endSpan(__instrumentsToken)
          }
          return {
            Instruments.current.recordEvent("Inside", attributes: .empty)
              return 1
          }()
        }()
        """,
      macros: macros
    )
  }

  @Test
  func spanMacroLowersNestedThrowingSpans() {
    assertMacroExpansion(
      """
      let value = #span("Outer") {
        try? #span("OptionalThrowing") {
          try throwingValue()
        }
        return try! #span("ForcedThrowing") {
          try throwingValue()
        }
      }
      """,
      expandedSource: """
        let value = {
          let __instrumentsRecorder = Instruments.current
          let __instrumentsToken = __instrumentsRecorder.beginSpan("Outer", attributes: .empty)
          defer {
            __instrumentsRecorder.endSpan(__instrumentsToken)
          }
          return {
            try? {
              let __instrumentsRecorder = Instruments.current
              let __instrumentsToken = __instrumentsRecorder.beginSpan("OptionalThrowing", attributes: .empty)
              defer {
                __instrumentsRecorder.endSpan(__instrumentsToken)
              }
              return try {
                try throwingValue()
              }()
            }()
              return try! {
              let __instrumentsRecorder = Instruments.current
              let __instrumentsToken = __instrumentsRecorder.beginSpan("ForcedThrowing", attributes: .empty)
              defer {
                __instrumentsRecorder.endSpan(__instrumentsToken)
              }
              return try {
                try throwingValue()
              }()
            }()
          }()
        }()
        """,
      macros: macros
    )
  }

  @Test
  func spanMacroLowersNestedAsyncThrowingSpans() {
    assertMacroExpansion(
      """
      let value = try await #span("Outer") {
        try await #span("Inner") {
          try await asyncThrowingValue()
        }
      }
      """,
      expandedSource: """
        let value = try await {
          let __instrumentsRecorder = Instruments.current
          let __instrumentsToken = __instrumentsRecorder.beginSpan("Outer", attributes: .empty)
          defer {
            __instrumentsRecorder.endSpan(__instrumentsToken)
          }
          return try await {
            try await {
              let __instrumentsRecorder = Instruments.current
              let __instrumentsToken = __instrumentsRecorder.beginSpan("Inner", attributes: .empty)
              defer {
                __instrumentsRecorder.endSpan(__instrumentsToken)
              }
              return try await {
                try await asyncThrowingValue()
              }()
            }()
          }()
        }()
        """,
      macros: macros.merging(["span": SpanAsyncThrowingMacro.self]) { _, asyncMacro in asyncMacro }
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
}
