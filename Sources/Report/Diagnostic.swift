public enum DiagnosticStateKind: String, Sendable, Codable {
  case measured
  case notConfigured
  case unavailable
  case failed
}

public struct DiagnosticState: Sendable, Equatable, Codable {
  public var kind: DiagnosticStateKind
  public var value: Double?
  public var unit: String?
  public var reason: String?

  public init(kind: DiagnosticStateKind, value: Double? = nil, unit: String? = nil, reason: String? = nil) {
    self.kind = kind
    self.value = value
    self.unit = unit
    self.reason = reason
  }

  public static func measured(_ value: Double, unit: String) -> DiagnosticState {
    DiagnosticState(kind: .measured, value: value, unit: unit)
  }

  public static func notConfigured(_ reason: String? = nil) -> DiagnosticState {
    DiagnosticState(kind: .notConfigured, reason: reason)
  }

  public static func unavailable(_ reason: String) -> DiagnosticState {
    DiagnosticState(kind: .unavailable, reason: reason)
  }

  public static func failed(_ reason: String) -> DiagnosticState {
    DiagnosticState(kind: .failed, reason: reason)
  }
}

public struct DiagnosticMetric: Sendable, Equatable, Codable {
  public var id: ReportID
  public var scope: ReportScope
  public var name: String
  public var state: DiagnosticState

  public init(id: ReportID, scope: ReportScope, name: String, state: DiagnosticState) {
    self.id = id
    self.scope = scope
    self.name = name
    self.state = state
  }
}

public struct DiagnosticAttachment: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    case file
    case trace
    case structuredData
    case url
    case note
  }

  public var id: ReportID
  public var scope: ReportScope
  public var kind: Kind
  public var title: String
  public var location: String
  public var contentType: String?
  public var metadata: [String: String]

  public init(
    id: ReportID,
    scope: ReportScope,
    kind: Kind,
    title: String,
    location: String,
    contentType: String? = nil,
    metadata: [String: String] = [:]
  ) {
    self.id = id
    self.scope = scope
    self.kind = kind
    self.title = title
    self.location = location
    self.contentType = contentType
    self.metadata = metadata
  }
}
