public protocol Recorder: Sendable {
  func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken
  func endSpan(_ token: SpanToken)
  func recordEvent(_ name: StaticString, attributes: SpanAttributes)
}

public extension Recorder {
  func beginSpan(_ name: StaticString) -> SpanToken {
    beginSpan(name, attributes: .empty)
  }

  func recordEvent(_ name: StaticString) {
    recordEvent(name, attributes: .empty)
  }

  func event(_ name: StaticString, attributes: SpanAttributes = .empty) {
    recordEvent(name, attributes: attributes)
  }

  func span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ operation: () throws -> T
  ) rethrows -> T {
    let token = beginSpan(name, attributes: attributes)
    defer {
      endSpan(token)
    }
    return try operation()
  }

  func span<T>(
    _ name: StaticString,
    attributes: SpanAttributes = .empty,
    _ operation: () async throws -> T
  ) async rethrows -> T {
    let token = beginSpan(name, attributes: attributes)
    defer {
      endSpan(token)
    }
    return try await operation()
  }
}
