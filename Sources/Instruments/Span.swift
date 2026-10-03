// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public struct Span: Sendable {
  public let name: StaticString
  public let attributes: SpanAttributes

  public init(_ name: StaticString, attributes: SpanAttributes = .empty) {
    self.name = name
    self.attributes = attributes
  }
}
