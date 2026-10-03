// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Dispatch

@testable import Instruments

enum InstrumentsCurrentIsolation {
  private static let semaphore = DispatchSemaphore(value: 1)

  static func withRecorder<T>(
    _ recorder: any Recorder,
    _ body: () throws -> T
  ) rethrows -> T {
    wait()
    defer {
      signal()
    }
    return try Instruments.withCurrentRecorder(recorder) {
      try body()
    }
  }

  static func withRecorder<T>(
    _ recorder: any Recorder,
    _ body: () async throws -> T
  ) async rethrows -> T {
    wait()
    defer {
      signal()
    }
    return try await Instruments.withCurrentRecorder(recorder) {
      try await body()
    }
  }

  private static func wait() {
    semaphore.wait()
  }

  private static func signal() {
    semaphore.signal()
  }
}
