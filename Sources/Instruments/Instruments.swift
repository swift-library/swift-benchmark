// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

public enum Instruments {
  public struct RecorderScope: Sendable {
    private let storage: RecorderScopeStorage

    fileprivate init(previousRecorder: any Recorder) {
      self.storage = RecorderScopeStorage(previousRecorder: previousRecorder)
    }

    public func restore() {
      storage.restore()
    }
  }

  public static var current: any Recorder {
    get {
      scopedRecorder ?? currentRecorderBox.get()
    }
    set {
      currentRecorderBox.set(newValue)
    }
  }

  public static func resetCurrentRecorder() {
    currentRecorderBox.set(defaultRecorder())
  }

  @discardableResult
  public static func beginCurrentRecorderScope(_ recorder: any Recorder) -> RecorderScope {
    let previous = current
    current = recorder
    return RecorderScope(previousRecorder: previous)
  }

  public static func withCurrentRecorder<T>(
    _ recorder: any Recorder,
    operation: () throws -> T
  ) rethrows -> T {
    try $scopedRecorder.withValue(recorder) {
      try operation()
    }
  }

  public static func withCurrentRecorder<T>(
    _ recorder: any Recorder,
    operation: () async throws -> T
  ) async rethrows -> T {
    try await $scopedRecorder.withValue(recorder) {
      try await operation()
    }
  }

  @TaskLocal private static var scopedRecorder: (any Recorder)?

  private static let currentRecorderBox = CurrentRecorderBox(defaultRecorder())

  private static func defaultRecorder() -> any Recorder {
    #if canImport(OSLog)
      SignpostRecorder()
    #else
      EmptyRecorder()
    #endif
  }
}

private final class RecorderScopeStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var previousRecorder: (any Recorder)?

  init(previousRecorder: any Recorder) {
    self.previousRecorder = previousRecorder
  }

  deinit {
    restore()
  }

  func restore() {
    let recorder = lock.withLock {
      let recorder = previousRecorder
      previousRecorder = nil
      return recorder
    }
    if let recorder {
      Instruments.current = recorder
    }
  }
}

private final class CurrentRecorderBox: @unchecked Sendable {
  private let lock = NSLock()
  private var recorder: any Recorder

  init(_ recorder: any Recorder) {
    self.recorder = recorder
  }

  func get() -> any Recorder {
    lock.withLock {
      recorder
    }
  }

  func set(_ recorder: any Recorder) {
    lock.withLock {
      self.recorder = recorder
    }
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
    lock()
    defer {
      unlock()
    }
    return try operation()
  }
}
