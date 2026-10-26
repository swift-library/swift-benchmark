// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

// The macros exist only while the package's `Macros` trait is enabled, which
// it is by default; without it, Instruments builds without swift-syntax.
#if Macros
  @freestanding(expression)
  public macro span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ body: () -> T
  ) -> T = #externalMacro(module: "InstrumentsMacro", type: "SpanMacro")

  @freestanding(expression)
  public macro span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ body: () throws -> T
  ) -> T = #externalMacro(module: "InstrumentsMacro", type: "SpanThrowingMacro")

  @freestanding(expression)
  public macro span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ body: () async -> T
  ) -> T = #externalMacro(module: "InstrumentsMacro", type: "SpanAsyncMacro")

  @freestanding(expression)
  public macro span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ body: () async throws -> T
  ) -> T = #externalMacro(module: "InstrumentsMacro", type: "SpanAsyncThrowingMacro")

  @freestanding(expression)
  public macro event(
    _ name: StaticString,
    attributes: SpanAttributes = .empty
  ) = #externalMacro(module: "InstrumentsMacro", type: "EventMacro")

  @attached(body)
  public macro Span(
    _ name: StaticString
  ) = #externalMacro(module: "InstrumentsMacro", type: "SpanAttributeMacro")

  @attached(body)
  public macro Instrumented() =
    #externalMacro(module: "InstrumentsMacro", type: "InstrumentedBodyMacro")

  @attached(memberAttribute)
  public macro InstrumentedMembers() =
    #externalMacro(module: "InstrumentsMacro", type: "InstrumentedMembersMacro")
#endif
