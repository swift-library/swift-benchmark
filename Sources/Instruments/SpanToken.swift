// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

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
