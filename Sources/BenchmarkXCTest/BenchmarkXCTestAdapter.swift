// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report

#if canImport(XCTest)
  import XCTest
#endif

public struct BenchmarkXCTestAdapter: Sendable {
  public var command: BenchmarkCommand

  public init(command: BenchmarkCommand = BenchmarkCommand()) {
    self.command = command
  }

  public func report(
    suites: [BenchmarkSuite],
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    baselineMetric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy = .relativePercentage(10),
    budgets: [BudgetPolicy] = []
  ) async throws -> ReportDocument {
    let output = try await command.run(
      suites: suites,
      metadata: metadata,
      baseline: baseline,
      baselineMetric: baselineMetric,
      threshold: threshold,
      budgets: budgets,
      format: .json
    )
    return try JSONDecoder().decode(ReportDocument.self, from: Data(output.utf8))
  }

  public func failureSummary(for document: ReportDocument) -> String? {
    guard document.summary.verdict == .failed else {
      return nil
    }
    return
      "Benchmark report \(document.metadata.id.rawValue) failed with \(document.summary.failedRegressionCount) regression(s), \(document.summary.failedBudgetCount) budget failure(s), and \(document.summary.failedDiagnosticCount) failed diagnostic(s)."
  }

  public func failureContexts(for document: ReportDocument) -> [BenchmarkXCTestFailureContext] {
    document.suites.flatMap { suite in
      suite.cases.flatMap { report in
        report.verdictCauses.map { cause in
          BenchmarkXCTestFailureContext(
            runID: document.metadata.id,
            suiteName: suite.name,
            caseName: report.name,
            verdict: report.verdict,
            cause: cause,
            sourceLocation: report.sourceLocation,
            message: "\(suite.name).\(report.name): \(cause.message)"
          )
        }
      }
    }
  }

  public func reportAttachmentPayloads(for document: ReportDocument) throws
    -> [BenchmarkXCTestAttachmentPayload]
  {
    let json = try JSONReportRenderer.render(document)
    return [
      BenchmarkXCTestAttachmentPayload(
        name: "swift-benchmark-report-\(document.metadata.id.rawValue).json",
        uniformTypeIdentifier: "public.json",
        content: json
      )
    ]
  }

  #if canImport(XCTest)
    public func assertNoFailures(
      in document: ReportDocument,
      file: StaticString = #filePath,
      line: UInt = #line
    ) {
      guard let summary = failureSummary(for: document) else {
        return
      }
      XCTFail(summary, file: file, line: line)
    }

    public func attachments(for document: ReportDocument) throws -> [XCTAttachment] {
      try reportAttachmentPayloads(for: document).map { payload in
        let attachment = XCTAttachment(string: payload.content)
        attachment.name = payload.name
        attachment.lifetime = .keepAlways
        return attachment
      }
    }
  #endif
}

public struct BenchmarkXCTestFailureContext: Sendable, Equatable {
  public var runID: ReportID
  public var suiteName: String
  public var caseName: String
  public var verdict: ReportVerdict
  public var cause: ReportVerdictCause
  public var sourceLocation: SourceLocationReport?
  public var message: String

  public init(
    runID: ReportID,
    suiteName: String,
    caseName: String,
    verdict: ReportVerdict,
    cause: ReportVerdictCause,
    sourceLocation: SourceLocationReport?,
    message: String
  ) {
    self.runID = runID
    self.suiteName = suiteName
    self.caseName = caseName
    self.verdict = verdict
    self.cause = cause
    self.sourceLocation = sourceLocation
    self.message = message
  }
}

public struct BenchmarkXCTestAttachmentPayload: Sendable, Equatable {
  public var name: String
  public var uniformTypeIdentifier: String
  public var content: String

  public init(name: String, uniformTypeIdentifier: String, content: String) {
    self.name = name
    self.uniformTypeIdentifier = uniformTypeIdentifier
    self.content = content
  }
}
