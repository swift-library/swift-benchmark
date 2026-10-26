// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

public struct ReportDocument: Sendable, Equatable, Codable {
  public var metadata: RunMetadata
  public var suites: [SuiteReport]
  /// Conditions that make the whole run's comparisons less trustworthy.
  public var warnings: [ReportWarning]
  public var summary: ReportSummary

  /// Creates a document from finished suite reports and run warnings.
  public init(metadata: RunMetadata, suites: [SuiteReport], warnings: [ReportWarning] = []) {
    self.metadata = metadata
    self.suites = suites
    self.warnings = warnings
    self.summary = ReportSummary(suites: suites, runWarnings: warnings)
  }

  private enum CodingKeys: String, CodingKey {
    case metadata, suites, warnings, summary
  }

  /// Decodes a report. A document this version cannot read, such as one an
  /// earlier version wrote, fails with an error that says to generate it
  /// again; the decoding failure is its underlying error.
  public init(from decoder: any Decoder) throws {
    do {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      metadata = try container.decode(RunMetadata.self, forKey: .metadata)
      suites = try container.decode([SuiteReport].self, forKey: .suites)
      warnings = try container.decode([ReportWarning].self, forKey: .warnings)
      summary = try container.decode(ReportSummary.self, forKey: .summary)
    } catch let error as DecodingError {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription:
            "This is not a report this version of swift-benchmark can read; generate it again.",
          underlyingError: error
        ))
    }
  }

  public init(
    metadata: RunMetadata,
    results: [BenchmarkResult],
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default,
    attributions: [TimelineAttribution] = [],
    attachments: [DiagnosticAttachment] = []
  ) {
    let groupedResults = Dictionary(grouping: results, by: \.suiteName)
    let suites = groupedResults.keys.sorted().map { suiteName -> SuiteReport in
      let suiteID = ReportIDFactory.suite(suiteName)
      let suiteResults = (groupedResults[suiteName] ?? []).sorted { $0.caseName < $1.caseName }
      let cases = suiteResults.map { result -> CaseReport in
        let caseID = ReportIDFactory.benchmarkCase(
          suiteName: result.suiteName,
          caseName: result.caseName
        )
        let scope = ReportScope(runID: metadata.id, suiteID: suiteID, caseID: caseID)
        let measurement = ReportDocument.reportMeasurement(from: result)
        let compared = comparison.compare(
          suiteName: result.suiteName,
          caseName: result.caseName,
          scope: scope,
          measurement: measurement,
          baseline: baseline
        )
        let sourceLocation = result.sourceLocation.map(SourceLocationReport.init)

        return CaseReport(
          id: caseID,
          scope: scope,
          name: result.caseName,
          sourceLocation: sourceLocation,
          configuration: BenchmarkConfigurationReport(result.configuration),
          tags: result.tags,
          measurement: measurement,
          baselines: compared.baselines,
          budgets: compared.budgets,
          dimensionCurves: Report.DimensionCurve.curves(
            suiteName: result.suiteName,
            caseName: result.caseName,
            scope: scope,
            measurement: measurement,
            sourceLocation: sourceLocation
          ),
          attributions: attributions.filter { $0.scope.caseID == caseID },
          attachments: attachments.filter { $0.scope.caseID == caseID },
          warnings: compared.warnings
        )
      }

      return SuiteReport(
        id: suiteID,
        scope: ReportScope(runID: metadata.id, suiteID: suiteID),
        name: suiteName,
        cases: cases
      )
    }

    self.init(
      metadata: metadata,
      suites: suites,
      warnings: ReportWarning.runWarnings(metadata: metadata, baseline: baseline)
    )
  }

  /// Replaces every case's baseline comparisons and budgets with the result
  /// of comparing it under `comparison`. Without a baseline, existing baseline
  /// comparisons are kept.
  public func comparing(
    baseline: BaselineDocument? = nil,
    comparison: ComparisonPolicy = .default
  ) -> ReportDocument {
    let suites = self.suites.map { suite in
      let cases = suite.cases.map { report in
        let compared = comparison.compare(
          suiteName: suite.name,
          caseName: report.name,
          scope: report.scope,
          measurement: report.measurement,
          baseline: baseline
        )
        let recompared = baseline != nil || !comparison.budgets.isEmpty
        return CaseReport(
          id: report.id,
          scope: report.scope,
          name: report.name,
          sourceLocation: report.sourceLocation,
          configuration: report.configuration,
          tags: report.tags,
          measurement: report.measurement,
          baselines: baseline == nil ? report.baselines : compared.baselines,
          budgets: comparison.budgets.isEmpty ? report.budgets : compared.budgets,
          dimensionCurves: report.dimensionCurves,
          attribution: report.attribution,
          attributions: report.attributions,
          attachments: report.attachments,
          status: report.status,
          warnings: recompared ? compared.warnings : report.warnings
        )
      }
      return SuiteReport(id: suite.id, scope: suite.scope, name: suite.name, cases: cases)
    }
    return ReportDocument(
      metadata: metadata,
      suites: suites,
      warnings: baseline == nil
        ? warnings : ReportWarning.runWarnings(metadata: metadata, baseline: baseline)
    )
  }

  private static func reportMeasurement(from result: BenchmarkResult) -> Report.Measurement {
    Report.Measurement(
      rows: result.measurement.rows.map { row in
        Report.Measurement.Row(
          id: row.id,
          size: row.size,
          arguments: row.arguments,
          samples: row.samples.map { sample in
            SampleReport(
              id: ReportIDFactory.sample(
                suiteName: result.suiteName,
                caseName: result.caseName,
                size: row.size,
                rowID: row.id,
                iteration: sample.iteration
              ),
              iterationID: ReportIDFactory.iteration(
                suiteName: result.suiteName,
                caseName: result.caseName,
                size: row.size,
                rowID: row.id,
                iteration: sample.iteration
              ),
              iteration: sample.iteration,
              batchSize: sample.batchSize,
              values: Dictionary(
                uniqueKeysWithValues: sample.values.map { ($0.key.name, $0.value) })
            )
          },
          metrics: Array(Set(row.samples.flatMap(\.values.keys))),
          allocationSites: row.allocationSites
        )
      }
    )
  }
}

extension SourceLocationReport {
  init(_ sourceLocation: BenchmarkSourceLocation) {
    self.init(
      fileID: sourceLocation.fileID,
      filePath: sourceLocation.filePath,
      line: sourceLocation.line,
      column: sourceLocation.column
    )
  }
}

extension BenchmarkConfigurationReport {
  init(_ configuration: BenchmarkConfiguration) {
    self.init(
      warmup: String(describing: configuration.warmup),
      iterations: String(describing: configuration.iterations),
      batching: String(describing: configuration.batching)
    )
  }
}
