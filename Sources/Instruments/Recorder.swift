// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public protocol Recorder: Sendable {
  func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken
  func endSpan(_ token: SpanToken)
  func recordEvent(_ name: StaticString, attributes: SpanAttributes)
}

extension Recorder {
  public func beginSpan(_ name: StaticString) -> SpanToken {
    beginSpan(name, attributes: .empty)
  }

  public func recordEvent(_ name: StaticString) {
    recordEvent(name, attributes: .empty)
  }

  public func event(_ name: StaticString, attributes: SpanAttributes = .empty) {
    recordEvent(name, attributes: attributes)
  }

  public func span<T>(
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

  public func span<T>(
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
