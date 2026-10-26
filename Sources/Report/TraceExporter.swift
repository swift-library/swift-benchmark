// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// Whether a run fails when an exporter has nothing for a case.
package enum DiagnosticRequirement: String, Sendable, Codable {
  case optional
  case required
}

/// Supplies the attachments, such as traces, that a case's report points to.
package protocol TraceExporter: Sendable {
  var requirement: DiagnosticRequirement { get }
  func attachments(for scope: ReportScope) async -> [DiagnosticAttachment]
}
