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
public macro Instrumented() = #externalMacro(module: "InstrumentsMacro", type: "InstrumentedBodyMacro")

@attached(memberAttribute)
public macro InstrumentedMembers() =
  #externalMacro(module: "InstrumentsMacro", type: "InstrumentedMembersMacro")
