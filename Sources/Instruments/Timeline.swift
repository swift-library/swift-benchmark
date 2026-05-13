public struct Timeline: Sendable, Equatable {
  public struct SpanID: RawRepresentable, Sendable, Hashable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }

    public static func < (lhs: SpanID, rhs: SpanID) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  public struct EventID: RawRepresentable, Sendable, Hashable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
      self.rawValue = rawValue
    }

    public static func < (lhs: EventID, rhs: EventID) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  public struct SpanRecord: Sendable, Equatable {
    public let id: SpanID
    public let parentID: SpanID?
    public let name: String
    public let start: UInt64
    public var end: UInt64?
    public let attributes: SpanAttributes

    public var duration: UInt64? {
      guard let end else {
        return nil
      }
      return end >= start ? end - start : 0
    }
  }

  public struct EventRecord: Sendable, Equatable {
    public let id: EventID
    public let parentSpanID: SpanID?
    public let name: String
    public let timestamp: UInt64
    public let attributes: SpanAttributes
  }

  public var spans: [SpanRecord]
  public var events: [EventRecord]

  public init(spans: [SpanRecord] = [], events: [EventRecord] = []) {
    self.spans = spans
    self.events = events
  }
}
