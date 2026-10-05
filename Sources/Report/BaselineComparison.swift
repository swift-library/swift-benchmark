// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

public enum ReportVerdict: String, Sendable, Codable {
  case passed
  case failed
  case notCompared
}

public struct ThresholdPolicy: Sendable, Equatable, Codable {
  public enum Kind: String, Sendable, Codable {
    case relativePercentage
    case absoluteNanoseconds
  }

  public var kind: Kind
  public var value: Double

  public init(kind: Kind, value: Double) {
    self.kind = kind
    self.value = value
  }

  public static func relativePercentage(_ percentage: Double) -> ThresholdPolicy {
    ThresholdPolicy(kind: .relativePercentage, value: percentage)
  }

  public static func absoluteNanoseconds(_ nanoseconds: Double) -> ThresholdPolicy {
    ThresholdPolicy(kind: .absoluteNanoseconds, value: nanoseconds)
  }
}

public struct BaselineCase: Sendable, Equatable, Codable {
  public var suiteName: String
  public var caseName: String
  public var meanNanoseconds: Double
  public var metrics: Report.Measurement.Metrics?
  public var measurement: Report.Measurement?

  public init(
    suiteName: String,
    caseName: String,
    meanNanoseconds: Double,
    metrics: Report.Measurement.Metrics? = nil,
    measurement: Report.Measurement? = nil
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.meanNanoseconds = meanNanoseconds
    self.metrics = metrics ?? measurement?.metrics
    self.measurement = measurement
  }

  public func value(for metric: Report.Measurement.Metric) -> Double {
    guard let metrics else {
      return meanNanoseconds
    }
    return metric.value(from: metrics)
  }
}

public struct BaselineDocument: Sendable, Equatable, Codable {
  public static let currentSchemaVersion = 2

  public var schemaVersion: Int
  public var metadata: RunMetadata?
  public var cases: [BaselineCase]

  public init(
    schemaVersion: Int = BaselineDocument.currentSchemaVersion,
    metadata: RunMetadata? = nil,
    cases: [BaselineCase]
  ) {
    self.schemaVersion = schemaVersion
    self.metadata = metadata
    self.cases = cases
  }

  public init(document: ReportDocument) {
    self.init(
      metadata: document.metadata,
      cases: document.suites.flatMap { suite in
        suite.cases.map { report in
          BaselineCase(
            suiteName: suite.name,
            caseName: report.name,
            meanNanoseconds: report.measurement.metrics.mean,
            metrics: report.measurement.metrics,
            measurement: report.measurement
          )
        }
      }
    )
  }

  public func baselineCase(suiteName: String, caseName: String) -> BaselineCase? {
    cases.first { baseline in
      baseline.suiteName == suiteName && baseline.caseName == caseName
    }
  }
}

public struct BaselineComparison: Sendable, Equatable, Codable {
  public var metric: Report.Measurement.Metric
  public var currentValueNanoseconds: Double
  public var baselineValueNanoseconds: Double
  public var currentMeanNanoseconds: Double
  public var baselineMeanNanoseconds: Double
  public var absoluteDeltaNanoseconds: Double
  public var percentageDelta: Double
  public var threshold: ThresholdPolicy
  public var verdict: ReportVerdict

  public init(
    currentMeanNanoseconds: Double,
    baselineMeanNanoseconds: Double,
    threshold: ThresholdPolicy
  ) {
    self.metric = .mean
    self.currentValueNanoseconds = currentMeanNanoseconds
    self.baselineValueNanoseconds = baselineMeanNanoseconds
    self.currentMeanNanoseconds = currentMeanNanoseconds
    self.baselineMeanNanoseconds = baselineMeanNanoseconds
    self.absoluteDeltaNanoseconds = currentMeanNanoseconds - baselineMeanNanoseconds
    if baselineMeanNanoseconds == 0 {
      self.percentageDelta = currentMeanNanoseconds == 0 ? 0 : Double.infinity
    } else {
      self.percentageDelta = (absoluteDeltaNanoseconds / baselineMeanNanoseconds) * 100
    }
    self.threshold = threshold
    self.verdict = BaselineComparison.evaluate(
      absoluteDeltaNanoseconds: absoluteDeltaNanoseconds,
      percentageDelta: percentageDelta,
      threshold: threshold
    )
  }

  public init(
    currentMetrics: Report.Measurement.Metrics,
    baselineCase: BaselineCase,
    metric: Report.Measurement.Metric = .mean,
    threshold: ThresholdPolicy
  ) {
    let currentValue = metric.value(from: currentMetrics)
    let baselineValue = baselineCase.value(for: metric)
    self.metric = metric
    self.currentValueNanoseconds = currentValue
    self.baselineValueNanoseconds = baselineValue
    self.currentMeanNanoseconds = currentMetrics.mean
    self.baselineMeanNanoseconds = baselineCase.meanNanoseconds
    self.absoluteDeltaNanoseconds = currentValue - baselineValue
    if baselineValue == 0 {
      self.percentageDelta = currentValue == 0 ? 0 : Double.infinity
    } else {
      self.percentageDelta = (absoluteDeltaNanoseconds / baselineValue) * 100
    }
    self.threshold = threshold
    self.verdict = BaselineComparison.evaluate(
      absoluteDeltaNanoseconds: absoluteDeltaNanoseconds,
      percentageDelta: percentageDelta,
      threshold: threshold
    )
  }

  private static func evaluate(
    absoluteDeltaNanoseconds: Double,
    percentageDelta: Double,
    threshold: ThresholdPolicy
  ) -> ReportVerdict {
    guard absoluteDeltaNanoseconds > 0 else {
      return .passed
    }

    switch threshold.kind {
    case .relativePercentage:
      return percentageDelta <= threshold.value ? .passed : .failed
    case .absoluteNanoseconds:
      return absoluteDeltaNanoseconds <= threshold.value ? .passed : .failed
    }
  }
}

extension BaselineComparison {
  private enum CodingKeys: String, CodingKey {
    case metric
    case currentValueNanoseconds
    case baselineValueNanoseconds
    case currentMeanNanoseconds
    case baselineMeanNanoseconds
    case absoluteDeltaNanoseconds
    case percentageDelta
    case threshold
    case verdict
  }

  /// Decodes a comparison. A `null` percentage delta comes from a zero baseline
  /// and decodes as an infinite delta with the sign of the absolute delta.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    metric = try container.decode(Report.Measurement.Metric.self, forKey: .metric)
    currentValueNanoseconds = try container.decode(Double.self, forKey: .currentValueNanoseconds)
    baselineValueNanoseconds = try container.decode(Double.self, forKey: .baselineValueNanoseconds)
    currentMeanNanoseconds = try container.decode(Double.self, forKey: .currentMeanNanoseconds)
    baselineMeanNanoseconds = try container.decode(Double.self, forKey: .baselineMeanNanoseconds)
    absoluteDeltaNanoseconds = try container.decode(Double.self, forKey: .absoluteDeltaNanoseconds)
    percentageDelta =
      try container.decodeIfPresent(Double.self, forKey: .percentageDelta)
      ?? (absoluteDeltaNanoseconds < 0 ? -.infinity : .infinity)
    threshold = try container.decode(ThresholdPolicy.self, forKey: .threshold)
    verdict = try container.decode(ReportVerdict.self, forKey: .verdict)
  }

  /// Encodes a comparison. JSON has no infinity, so the infinite percentage
  /// delta of a zero baseline is encoded as `null`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(metric, forKey: .metric)
    try container.encode(currentValueNanoseconds, forKey: .currentValueNanoseconds)
    try container.encode(baselineValueNanoseconds, forKey: .baselineValueNanoseconds)
    try container.encode(currentMeanNanoseconds, forKey: .currentMeanNanoseconds)
    try container.encode(baselineMeanNanoseconds, forKey: .baselineMeanNanoseconds)
    try container.encode(absoluteDeltaNanoseconds, forKey: .absoluteDeltaNanoseconds)
    if percentageDelta.isFinite {
      try container.encode(percentageDelta, forKey: .percentageDelta)
    } else {
      try container.encodeNil(forKey: .percentageDelta)
    }
    try container.encode(threshold, forKey: .threshold)
    try container.encode(verdict, forKey: .verdict)
  }
}

public struct BudgetPolicy: Sendable, Equatable, Codable {
  public var suiteName: String?
  public var caseName: String?
  public var metric: Report.Measurement.Metric
  public var limitNanoseconds: Double

  public init(
    suiteName: String? = nil,
    caseName: String? = nil,
    metric: Report.Measurement.Metric = .mean,
    limitNanoseconds: Double
  ) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.metric = metric
    self.limitNanoseconds = limitNanoseconds
  }

  public func applies(suiteName: String, caseName: String) -> Bool {
    if let suiteNameFilter = self.suiteName, suiteNameFilter != suiteName {
      return false
    }
    if let caseNameFilter = self.caseName, caseNameFilter != caseName {
      return false
    }
    return true
  }
}

public struct BudgetComparison: Sendable, Equatable, Codable {
  public var policy: BudgetPolicy
  public var actualNanoseconds: Double
  public var absoluteDeltaNanoseconds: Double
  public var verdict: ReportVerdict

  public init(policy: BudgetPolicy, metrics: Report.Measurement.Metrics) {
    self.policy = policy
    self.actualNanoseconds = policy.metric.value(from: metrics)
    self.absoluteDeltaNanoseconds = actualNanoseconds - policy.limitNanoseconds
    self.verdict = actualNanoseconds <= policy.limitNanoseconds ? .passed : .failed
  }
}
