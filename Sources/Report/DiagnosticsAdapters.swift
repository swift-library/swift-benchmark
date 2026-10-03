// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public enum DiagnosticRequirement: String, Sendable, Codable {
  case optional
  case required
}

public protocol BenchmarkObserver: Sendable {
  func runDidStart(scope: ReportScope) async
  func runDidFinish(scope: ReportScope) async
}

extension BenchmarkObserver {
  public func runDidStart(scope: ReportScope) async {}
  public func runDidFinish(scope: ReportScope) async {}
}

public protocol MetricProvider: Sendable {
  var requirement: DiagnosticRequirement { get }
  func metrics(for scope: ReportScope) async -> [DiagnosticMetric]
}

public protocol TraceExporter: Sendable {
  var requirement: DiagnosticRequirement { get }
  func attachments(for scope: ReportScope) async -> [DiagnosticAttachment]
}

public protocol ReportAttributor: Sendable {
  func attribute(
    document: ReportDocument,
    diagnostics: [DiagnosticMetric],
    attachments: [DiagnosticAttachment]
  ) -> ReportDocument
}

public struct NoopBenchmarkObserver: BenchmarkObserver {
  public init() {}
}

public struct UnavailableMetricProvider: MetricProvider {
  public var requirement: DiagnosticRequirement
  public var metricName: String
  public var reason: String

  public init(
    metricName: String,
    reason: String,
    requirement: DiagnosticRequirement = .optional
  ) {
    self.metricName = metricName
    self.reason = reason
    self.requirement = requirement
  }

  public func metrics(for scope: ReportScope) async -> [DiagnosticMetric] {
    [
      DiagnosticMetric(
        id: ReportID(rawValue: "metric:\(ReportIDFactory.stable(metricName))"),
        scope: scope,
        name: metricName,
        state: .unavailable(reason)
      )
    ]
  }
}

public struct StaticTraceExporter: TraceExporter {
  public var requirement: DiagnosticRequirement
  public var attachment: DiagnosticAttachment

  public init(attachment: DiagnosticAttachment, requirement: DiagnosticRequirement = .optional) {
    self.attachment = attachment
    self.requirement = requirement
  }

  public func attachments(for scope: ReportScope) async -> [DiagnosticAttachment] {
    [
      DiagnosticAttachment(
        id: attachment.id,
        scope: scope,
        kind: attachment.kind,
        title: attachment.title,
        location: attachment.location,
        contentType: attachment.contentType,
        metadata: attachment.metadata
      )
    ]
  }
}
