// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import MacroTesting
import SwiftSyntaxMacros
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

  @Test
  func spanAttributeMacroInstrumentsInitializerBody() {
    assertMacroExpansion(
      """
      struct Store {
        let path: String

        @Span("Store.customInit")
        init(path: String) {
          self.path = path
        }
      }
      """,
      expandedSource: """
        struct Store {
          let path: String
          init(path: String) {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.customInit", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.path = path
          }
        }
        """,
      macros: macros
    )
  }

  @Test
  func instrumentedInitializerInfersTypeAndLabels() {
    assertMacroExpansion(
      """
      struct Store {
        let path: String

        @Instrumented
        init(_ path: String, mode: String) {
          self.path = path + mode
        }
      }
      """,
      expandedSource: """
        struct Store {
          let path: String
          init(_ path: String, mode: String) {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.init(_:mode:)", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.path = path + mode
          }
        }
        """,
      macros: macros
    )
  }

  @Test
  func spanAttributeMacroPreservesInitializerShapes() {
    assertMacroExpansion(
      """
      final class Store: BaseStore {
        let path: String

        @Span("Store.required")
        required init?<Value>(_ value: Value) throws where Value: CustomStringConvertible {
          self.path = value.description
          try super.init()
        }

        @Span("Store.convenience")
        convenience init(flag: Bool) {
          self.init(path: String(flag))
        }

        init(path: String) {
          self.path = path
          super.init()
        }
      }
      """,
      expandedSource: """
        final class Store: BaseStore {
          let path: String
          required init?<Value>(_ value: Value) throws where Value: CustomStringConvertible {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.required", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.path = value.description
            try super.init()
          }
          convenience init(flag: Bool) {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.convenience", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.init(path: String(flag))
          }

          init(path: String) {
            self.path = path
            super.init()
          }
        }
        """,
      macros: macros
    )
  }

  @Test
  func instrumentedMembersMacroInstrumentsFunctionsAndInitializers() {
    assertMacroExpansion(
      """
      @InstrumentedMembers
      struct Store {
        let path: String

        init() {
          self.path = ""
        }

        init(path: String) {
          self.path = path
        }

        init(_ path: String, mode: String) {
          self.path = path + mode
        }

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
          let path: String

          init() {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.init()", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.path = ""
          }

          init(path: String) {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.init(path:)", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.path = path
          }

          init(_ path: String, mode: String) {
            let __instrumentsRecorder = Instruments.current
            let __instrumentsToken = __instrumentsRecorder.beginSpan("Store.init(_:mode:)", attributes: .empty)
            defer {
              __instrumentsRecorder.endSpan(__instrumentsToken)
            }
            self.path = path + mode
          }

          func load() -> Int {
            let __instrumentsRecorder = Instruments.current
            return __instrumentsRecorder.span("Store.load", attributes: .empty) {
                1
              }
          }

          var count: Int {
            2
          }
        }
        """,
      macros: macros
    )
  }

  @Test
  func instrumentedMembersMacroSkipsAlreadyInstrumentedInitializers() {
    assertMacroExpansion(
      """
      @InstrumentedMembers
      struct Store {
        let path: String

        @Span("manual")
        init(manual: String) {
          self.path = manual
        }

        @Instrumented
        init(alias: String) {
          self.path = alias
        }
      }
      """,
      expandedSource: """
        struct Store {
          let path: String

          @Span("manual")
          init(manual: String) {
            self.path = manual
          }

          @Instrumented
          init(alias: String) {
            self.path = alias
          }
        }
        """,
      macros: ["InstrumentedMembers": InstrumentedMembersMacro.self]
    )
  }
}
