// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report

#if canImport(XCTest)
  import XCTest
#endif

public struct BenchmarkXCTestAdapter: Sendable {
  /// The runner that measures the suites.
  public var runner: BenchmarkRunner

  /// Creates an adapter that measures with `runner`.
  public init(runner: BenchmarkRunner = BenchmarkRunner()) {
    self.runner = runner
  }

  /// Measures `suites` in this process and reports them, compared with
  /// `baseline` when one is given.
  public func report(
    suites: [BenchmarkSuite],
    metadata: RunMetadata,
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default
  ) async throws -> ReportDocument {
    try await BenchmarkCommand(runner: runner).report(
      plan: BenchmarkRunner.Plan(suites: suites),
      metadata: metadata,
      baseline: baseline,
      comparison: comparison
    )
  }

  public func failureSummary(for document: ReportDocument) -> String? {
    guard document.summary.verdict == .failed else {
      return nil
    }
    return
      "Benchmark report \(document.metadata.id.rawValue) failed with \(document.summary.failedRegressionCount) regression(s) and \(document.summary.failedBudgetCount) budget failure(s)."
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
  #endif

  // swift-corelibs-xctest has no XCTAttachment.
  #if canImport(XCTest) && canImport(Darwin)
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
