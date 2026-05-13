#if canImport(OSLog)
import OSLog

public struct SignpostRecorder: Recorder {
  private let signposter: OSSignposter

  public init(subsystem: String = "swift-benchmark", category: String = "Instruments") {
    self.signposter = OSSignposter(subsystem: subsystem, category: category)
  }

  public func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken {
    let state = signposter.beginInterval(name)
    return SpanToken(storage: SignpostSpanTokenStorage(signposter: signposter, name: name, state: state))
  }

  public func endSpan(_ token: SpanToken) {
    guard let storage = token.storage as? SignpostSpanTokenStorage else {
      return
    }
    storage.signposter.endInterval(storage.name, storage.state)
  }

  public func recordEvent(_ name: StaticString, attributes: SpanAttributes) {
    signposter.emitEvent(name)
  }
}

private struct SignpostSpanTokenStorage: SpanTokenStorage {
  let signposter: OSSignposter
  let name: StaticString
  let state: OSSignpostIntervalState
}
#endif
