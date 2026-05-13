import Dispatch

@testable import Instruments

enum InstrumentsCurrentIsolation {
  private static let semaphore = DispatchSemaphore(value: 1)

  static func withRecorder<T>(
    _ recorder: any Recorder,
    _ body: () throws -> T
  ) rethrows -> T {
    wait()
    let previous = Instruments.current
    Instruments.current = recorder
    defer {
      Instruments.current = previous
      signal()
    }
    return try body()
  }

  static func withRecorder<T>(
    _ recorder: any Recorder,
    _ body: () async throws -> T
  ) async rethrows -> T {
    wait()
    let previous = Instruments.current
    Instruments.current = recorder
    defer {
      Instruments.current = previous
      signal()
    }
    return try await body()
  }

  private static func wait() {
    semaphore.wait()
  }

  private static func signal() {
    semaphore.signal()
  }
}
