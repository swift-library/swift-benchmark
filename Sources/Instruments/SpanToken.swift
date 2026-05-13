public struct SpanToken: Sendable {
  internal let storage: any SpanTokenStorage

  internal init(storage: some SpanTokenStorage) {
    self.storage = storage
  }

  public static var empty: SpanToken {
    SpanToken(storage: EmptySpanTokenStorage())
  }
}

internal protocol SpanTokenStorage: Sendable {}

internal struct EmptySpanTokenStorage: SpanTokenStorage {}
