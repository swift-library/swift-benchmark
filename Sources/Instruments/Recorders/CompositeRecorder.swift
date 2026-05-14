public struct CompositeRecorder: Recorder {
  public let recorders: [any Recorder]

  public init(_ recorders: [any Recorder]) {
    self.recorders = recorders
  }

  public func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken {
    guard !recorders.isEmpty else {
      return .empty
    }
    let entries = recorders.map { recorder in
      CompositeSpanTokenEntry(
        recorder: recorder,
        token: recorder.beginSpan(name, attributes: attributes)
      )
    }
    return SpanToken(storage: CompositeSpanTokenStorage(entries: entries))
  }

  public func endSpan(_ token: SpanToken) {
    guard let storage = token.storage as? CompositeSpanTokenStorage else {
      return
    }
    for entry in storage.entries.reversed() {
      entry.recorder.endSpan(entry.token)
    }
  }

  public func recordEvent(_ name: StaticString, attributes: SpanAttributes) {
    for recorder in recorders {
      recorder.recordEvent(name, attributes: attributes)
    }
  }
}

private struct CompositeSpanTokenStorage: SpanTokenStorage {
  let entries: [CompositeSpanTokenEntry]
}

private struct CompositeSpanTokenEntry: Sendable {
  let recorder: any Recorder
  let token: SpanToken
}
