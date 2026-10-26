// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// A file or location produced alongside a run, such as an Instruments trace,
/// that a case's report points to.
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
