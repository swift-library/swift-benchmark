import Benchmark
import Foundation
import Report

#if canImport(Testing)
  import Testing
#endif

public struct BenchmarkTestingAdapter: Sendable {
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
    return "Benchmark report \(document.metadata.id.rawValue) failed with \(document.summary.failedRegressionCount) regression(s), \(document.summary.failedBudgetCount) budget failure(s), and \(document.summary.failedDiagnosticCount) failed diagnostic(s)."
  }

  public func failureContexts(for document: ReportDocument) -> [BenchmarkAdapterFailureContext] {
    document.suites.flatMap { suite in
      suite.cases.flatMap { report in
        report.verdictCauses.map { cause in
          BenchmarkAdapterFailureContext(
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

  #if canImport(Testing)
    public func recordIssues(for document: ReportDocument) {
      let contexts = failureContexts(for: document)
      guard !contexts.isEmpty else {
        return
      }
      for context in contexts {
        Issue.record(BenchmarkTestingFailure(message: context.message))
      }
    }
  #endif
}

public struct BenchmarkAdapterFailureContext: Sendable, Equatable {
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

#if canImport(Testing)
  private struct BenchmarkTestingFailure: Error, CustomStringConvertible {
    var message: String

    var description: String {
      message
    }
  }
#endif
