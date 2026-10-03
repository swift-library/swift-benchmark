// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

@inline(never)
public func blackHole<T>(_ value: T) {
  withUnsafePointer(to: value) { pointer in
    _ = pointer
  }
  _fixLifetime(value)
}
