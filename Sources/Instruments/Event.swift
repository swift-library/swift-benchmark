public struct Event: Sendable {
  public let name: StaticString
  public let attributes: SpanAttributes

  public init(_ name: StaticString, attributes: SpanAttributes = .empty) {
    self.name = name
    self.attributes = attributes
  }
}
