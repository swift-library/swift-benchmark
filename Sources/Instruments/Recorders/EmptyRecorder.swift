public struct EmptyRecorder: Recorder {
  public init() {}

  public func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken {
    .empty
  }

  public func endSpan(_ token: SpanToken) {}

  public func recordEvent(_ name: StaticString, attributes: SpanAttributes) {}
}
