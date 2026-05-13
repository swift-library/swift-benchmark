import Foundation

public enum Instruments {
  public static var current: any Recorder {
    get {
      currentRecorderBox.get()
    }
    set {
      currentRecorderBox.set(newValue)
    }
  }

  public static func resetCurrentRecorder() {
    currentRecorderBox.set(defaultRecorder())
  }

  private static let currentRecorderBox = CurrentRecorderBox(defaultRecorder())

  private static func defaultRecorder() -> any Recorder {
    #if canImport(OSLog)
    SignpostRecorder()
    #else
    EmptyRecorder()
    #endif
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
