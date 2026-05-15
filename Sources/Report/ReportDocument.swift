import Benchmark

public enum ReportExecutionStatus: String, Sendable, Codable {
  case passed
  case failed
  case unavailable
}

public struct ReportVerdictCause: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    case executionFailed
    case baselineRegression
    case budgetExceeded
    case diagnosticFailed
  }

  public var kind: Kind
  public var scope: ReportScope
  public var message: String
  public var metric: Report.Measurement.Metric?
  public var actualNanoseconds: Double?
  public var expectedNanoseconds: Double?
  public var deltaNanoseconds: Double?
  public var percentageDelta: Double?
  public var diagnosticID: ReportID?
  public var budget: BudgetPolicy?

  public init(
    kind: Kind,
    scope: ReportScope,
    message: String,
    metric: Report.Measurement.Metric? = nil,
    actualNanoseconds: Double? = nil,
    expectedNanoseconds: Double? = nil,
    deltaNanoseconds: Double? = nil,
    percentageDelta: Double? = nil,
    diagnosticID: ReportID? = nil,
    budget: BudgetPolicy? = nil
  ) {
    self.kind = kind
    self.scope = scope
    self.message = message
    self.metric = metric
    self.actualNanoseconds = actualNanoseconds
    self.expectedNanoseconds = expectedNanoseconds
    self.deltaNanoseconds = deltaNanoseconds
    self.percentageDelta = percentageDelta
    self.diagnosticID = diagnosticID
    self.budget = budget
  }
}

public struct CaseReport: Sendable, Equatable, Codable {
  public var id: ReportID
  public var scope: ReportScope
  public var name: String
  public var sourceLocation: SourceLocationReport?
  public var configuration: BenchmarkConfigurationReport
  public var tags: [String]
  public var measurement: Report.Measurement
  public var baseline: BaselineComparison?
  public var budgets: [BudgetComparison]
  public var dimensionCurves: [Report.DimensionCurve]
  public var attribution: TimelineAttribution?
  public var attributions: [TimelineAttribution]
  public var diagnostics: [DiagnosticMetric]
  public var attachments: [DiagnosticAttachment]
  public var status: ReportExecutionStatus
  public var verdict: ReportVerdict
  public var verdictCauses: [ReportVerdictCause]

  public var samples: [SampleReport] {
    measurement.samples
  }

  public var metrics: Report.Measurement.Metrics {
    measurement.metrics
  }

  public init(
    id: ReportID,
    scope: ReportScope,
    name: String,
    sourceLocation: SourceLocationReport? = nil,
    configuration: BenchmarkConfigurationReport,
    tags: [String] = [],
    measurement: Report.Measurement,
    baseline: BaselineComparison? = nil,
    budgets: [BudgetComparison] = [],
    dimensionCurves: [Report.DimensionCurve] = [],
    attribution: TimelineAttribution? = nil,
    attributions: [TimelineAttribution]? = nil,
    diagnostics: [DiagnosticMetric] = [],
    attachments: [DiagnosticAttachment] = [],
    status: ReportExecutionStatus = .passed,
    verdictCauses: [ReportVerdictCause]? = nil
  ) {
    self.id = id
    self.scope = scope
    self.name = name
    self.sourceLocation = sourceLocation
    self.configuration = configuration
    self.tags = tags
    self.measurement = measurement
    self.baseline = baseline
    self.budgets = budgets
    self.dimensionCurves = dimensionCurves
    self.attributions = attributions ?? attribution.map { [$0] } ?? []
    self.attribution = attribution ?? self.attributions.first
    self.diagnostics = diagnostics
    self.attachments = attachments
    self.status = status
    self.verdictCauses = verdictCauses ?? CaseReport.makeVerdictCauses(
      scope: scope,
      status: status,
      baseline: baseline,
      budgets: budgets,
      diagnostics: diagnostics
    )
    if !self.verdictCauses.isEmpty {
      self.verdict = .failed
    } else if baseline != nil || !budgets.isEmpty {
      self.verdict = .passed
    } else {
      self.verdict = .notCompared
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case scope
    case name
    case sourceLocation
    case configuration
    case tags
    case measurement
    case baseline
    case budgets
    case dimensionCurves
    case attribution
    case attributions
    case diagnostics
    case attachments
    case status
    case verdict
    case verdictCauses
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(ReportID.self, forKey: .id)
    let scope = try container.decode(ReportScope.self, forKey: .scope)
    let name = try container.decode(String.self, forKey: .name)
    let sourceLocation = try container.decodeIfPresent(
      SourceLocationReport.self,
      forKey: .sourceLocation
    )
    let configuration = try container.decode(
      BenchmarkConfigurationReport.self,
      forKey: .configuration
    )
    let tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    let measurement = try container.decode(Report.Measurement.self, forKey: .measurement)
    let baseline = try container.decodeIfPresent(BaselineComparison.self, forKey: .baseline)
    let budgets = try container.decodeIfPresent([BudgetComparison].self, forKey: .budgets) ?? []
    let dimensionCurves = try container.decodeIfPresent(
      [Report.DimensionCurve].self,
      forKey: .dimensionCurves
    ) ?? []
    let attribution = try container.decodeIfPresent(
      TimelineAttribution.self,
      forKey: .attribution
    )
    let attributions = try container.decodeIfPresent(
      [TimelineAttribution].self,
      forKey: .attributions
    )
    let diagnostics = try container.decodeIfPresent(
      [DiagnosticMetric].self,
      forKey: .diagnostics
    ) ?? []
    let attachments = try container.decodeIfPresent(
      [DiagnosticAttachment].self,
      forKey: .attachments
    ) ?? []
    let status = try container.decodeIfPresent(
      ReportExecutionStatus.self,
      forKey: .status
    ) ?? .passed
    let verdictCauses = try container.decodeIfPresent(
      [ReportVerdictCause].self,
      forKey: .verdictCauses
    )

    self.init(
      id: id,
      scope: scope,
      name: name,
      sourceLocation: sourceLocation,
      configuration: configuration,
      tags: tags,
      measurement: measurement,
      baseline: baseline,
      budgets: budgets,
      dimensionCurves: dimensionCurves,
      attribution: attribution,
      attributions: attributions,
      diagnostics: diagnostics,
      attachments: attachments,
      status: status,
      verdictCauses: verdictCauses
    )

    if let verdict = try container.decodeIfPresent(ReportVerdict.self, forKey: .verdict) {
      self.verdict = verdict
    }
  }

  private static func makeVerdictCauses(
    scope: ReportScope,
    status: ReportExecutionStatus,
    baseline: BaselineComparison?,
    budgets: [BudgetComparison],
    diagnostics: [DiagnosticMetric]
  ) -> [ReportVerdictCause] {
    var causes: [ReportVerdictCause] = []
    if status == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .executionFailed,
          scope: scope,
          message: "Benchmark execution failed."
        )
      )
    }
    if let baseline, baseline.verdict == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .baselineRegression,
          scope: scope,
          message: "Baseline regression for \(baseline.metric.rawValue).",
          metric: baseline.metric,
          actualNanoseconds: baseline.currentValueNanoseconds,
          expectedNanoseconds: baseline.baselineValueNanoseconds,
          deltaNanoseconds: baseline.absoluteDeltaNanoseconds,
          percentageDelta: baseline.percentageDelta
        )
      )
    }
    for budget in budgets where budget.verdict == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .budgetExceeded,
          scope: scope,
          message: "Budget exceeded for \(budget.policy.metric.rawValue).",
          metric: budget.policy.metric,
          actualNanoseconds: budget.actualNanoseconds,
          expectedNanoseconds: budget.policy.limitNanoseconds,
          deltaNanoseconds: budget.absoluteDeltaNanoseconds,
          budget: budget.policy
        )
      )
    }
    for diagnostic in diagnostics where diagnostic.state.kind == .failed {
      causes.append(
        ReportVerdictCause(
          kind: .diagnosticFailed,
          scope: diagnostic.scope,
          message: diagnostic.state.reason ?? "Diagnostic '\(diagnostic.name)' failed.",
          diagnosticID: diagnostic.id
        )
      )
    }
    return causes
  }
}

public struct SuiteReport: Sendable, Equatable, Codable {
  public var id: ReportID
  public var scope: ReportScope
  public var name: String
  public var cases: [CaseReport]

  public init(id: ReportID, scope: ReportScope, name: String, cases: [CaseReport]) {
    self.id = id
    self.scope = scope
    self.name = name
    self.cases = cases
  }
}

public struct ReportSummary: Sendable, Equatable, Codable {
  public var suiteCount: Int
  public var caseCount: Int
  public var failedRegressionCount: Int
  public var failedBudgetCount: Int
  public var unavailableDiagnosticCount: Int
  public var failedDiagnosticCount: Int
  public var verdict: ReportVerdict

  public init(suites: [SuiteReport]) {
    self.suiteCount = suites.count
    self.caseCount = suites.reduce(0) { $0 + $1.cases.count }
    self.failedRegressionCount = suites.reduce(0) { partial, suite in
      partial + suite.cases.filter { $0.baseline?.verdict == .failed }.count
    }
    self.failedBudgetCount = suites.reduce(0) { partial, suite in
      partial + suite.cases.reduce(0) { casePartial, report in
        casePartial + report.budgets.filter { $0.verdict == .failed }.count
      }
    }
    self.unavailableDiagnosticCount = suites.reduce(0) { partial, suite in
      partial + suite.cases.reduce(0) { casePartial, report in
        casePartial + report.diagnostics.filter { $0.state.kind == .unavailable }.count
      }
    }
    self.failedDiagnosticCount = suites.reduce(0) { partial, suite in
      partial + suite.cases.reduce(0) { casePartial, report in
        casePartial + report.diagnostics.filter { $0.state.kind == .failed }.count
      }
    }
    self.verdict =
      failedRegressionCount == 0 && failedBudgetCount == 0 && failedDiagnosticCount == 0
      ? .passed : .failed
  }
}

public struct ReportDocument: Sendable, Equatable, Codable {
  public static let currentSchemaVersion = 2

  public var schemaVersion: Int
  public var metadata: RunMetadata
  public var suites: [SuiteReport]
  public var summary: ReportSummary

  public init(
    schemaVersion: Int = ReportDocument.currentSchemaVersion,
    metadata: RunMetadata,
    suites: [SuiteReport]
  ) {
    self.schemaVersion = schemaVersion
    self.metadata = metadata
    self.suites = suites
    self.summary = ReportSummary(suites: suites)
  }

  public init(
    metadata: RunMetadata,
    results: [BenchmarkResult],
    baseline: BaselineDocument? = nil,
    baselineMetric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy = .relativePercentage(10),
    budgets: [BudgetPolicy] = [],
    attributions: [TimelineAttribution] = [],
    diagnostics: [DiagnosticMetric] = [],
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
        let baselineComparison = baseline?
          .baselineCase(suiteName: result.suiteName, caseName: result.caseName)
          .map { baselineCase in
            BaselineComparison(
              currentMetrics: measurement.metrics,
              baselineCase: baselineCase,
              metric: baselineMetric,
              threshold: threshold
            )
          }
        let budgetComparisons = budgets
          .filter { $0.applies(suiteName: result.suiteName, caseName: result.caseName) }
          .map { BudgetComparison(policy: $0, metrics: measurement.metrics) }
        let sourceLocation = result.sourceLocation.map(SourceLocationReport.init)

        return CaseReport(
          id: caseID,
          scope: scope,
          name: result.caseName,
          sourceLocation: sourceLocation,
          configuration: BenchmarkConfigurationReport(result.configuration),
          tags: result.tags,
          measurement: measurement,
          baseline: baselineComparison,
          budgets: budgetComparisons,
          dimensionCurves: ReportDocument.dimensionCurves(
            suiteName: result.suiteName,
            caseName: result.caseName,
            scope: scope,
            measurement: measurement,
            sourceLocation: sourceLocation
          ),
          attributions: attributions.filter { $0.scope.caseID == caseID },
          diagnostics: diagnostics.filter { $0.scope.caseID == caseID },
          attachments: attachments.filter { $0.scope.caseID == caseID }
        )
      }

      return SuiteReport(
        id: suiteID,
        scope: ReportScope(runID: metadata.id, suiteID: suiteID),
        name: suiteName,
        cases: cases
      )
    }

    self.init(metadata: metadata, suites: suites)
  }

  public func comparing(
    baseline: BaselineDocument? = nil,
    baselineMetric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy = .relativePercentage(10),
    budgets: [BudgetPolicy] = []
  ) -> ReportDocument {
    let suites = self.suites.map { suite in
      let cases = suite.cases.map { report in
        let baselineComparison = baseline?
          .baselineCase(suiteName: suite.name, caseName: report.name)
          .map { baselineCase in
            BaselineComparison(
              currentMetrics: report.measurement.metrics,
              baselineCase: baselineCase,
              metric: baselineMetric,
              threshold: threshold
            )
          } ?? report.baseline
        let budgetComparisons =
          budgets.isEmpty
          ? report.budgets
          : budgets
            .filter { $0.applies(suiteName: suite.name, caseName: report.name) }
            .map { BudgetComparison(policy: $0, metrics: report.measurement.metrics) }

        return CaseReport(
          id: report.id,
          scope: report.scope,
          name: report.name,
          sourceLocation: report.sourceLocation,
          configuration: report.configuration,
          tags: report.tags,
          measurement: report.measurement,
          baseline: baselineComparison,
          budgets: budgetComparisons,
          dimensionCurves: report.dimensionCurves,
          attribution: report.attribution,
          attributions: report.attributions,
          diagnostics: report.diagnostics,
          attachments: report.attachments,
          status: report.status
        )
      }
      return SuiteReport(id: suite.id, scope: suite.scope, name: suite.name, cases: cases)
    }
    return ReportDocument(schemaVersion: schemaVersion, metadata: metadata, suites: suites)
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
              durationNanoseconds: sample.durationNanoseconds
            )
          }
        )
      }
    )
  }

  private static func dimensionCurves(
    suiteName: String,
    caseName: String,
    scope: ReportScope,
    measurement: Report.Measurement,
    sourceLocation: SourceLocationReport?
  ) -> [Report.DimensionCurve] {
    let dimensionRows = measurement.rows.compactMap { row -> Report.Measurement.Row? in
      row.size == nil ? nil : row
    }
    guard !dimensionRows.isEmpty else {
      return []
    }

    return [.mean, .median, .p95].map { metric in
      Report.DimensionCurve(
        id: ReportIDFactory.dimensionCurve(suiteName: suiteName, caseName: caseName, metric: metric),
        scope: ReportScope(
          runID: scope.runID,
          suiteID: scope.suiteID,
          caseID: scope.caseID,
          dimensionCurveID: ReportIDFactory.dimensionCurve(
            suiteName: suiteName,
            caseName: caseName,
            metric: metric
          )
        ),
        metric: metric,
        points: dimensionRows.compactMap { row in
          guard let size = row.size else {
            return nil
          }
          let value = metric.value(from: row.metrics)
          return Report.DimensionCurve.Point(
            size: size,
            valueNanoseconds: value,
            amortizedNanosecondsPerUnit: Benchmark.Dimension.amortized(value, by: size),
            sampleCount: row.samples.count,
            sourceLocation: sourceLocation
          )
        }
      )
    }
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
      iterations: String(describing: configuration.iterations)
    )
  }
}
