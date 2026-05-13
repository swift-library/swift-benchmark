import Benchmark
import Foundation

public struct ReportID: RawRepresentable, Sendable, Hashable, Codable, Comparable,
  ExpressibleByStringLiteral, CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public var description: String {
    rawValue
  }

  public static func < (lhs: ReportID, rhs: ReportID) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct ReportScope: Sendable, Hashable, Codable {
  public var runID: ReportID
  public var suiteID: ReportID?
  public var caseID: ReportID?
  public var iterationID: ReportID?
  public var sampleID: ReportID?
  public var spanID: ReportID?
  public var eventID: ReportID?
  public var metricID: ReportID?
  public var attachmentID: ReportID?
  public var rowID: ReportID?
  public var dimensionCurveID: ReportID?

  public init(
    runID: ReportID,
    suiteID: ReportID? = nil,
    caseID: ReportID? = nil,
    iterationID: ReportID? = nil,
    sampleID: ReportID? = nil,
    spanID: ReportID? = nil,
    eventID: ReportID? = nil,
    metricID: ReportID? = nil,
    attachmentID: ReportID? = nil,
    rowID: ReportID? = nil,
    dimensionCurveID: ReportID? = nil
  ) {
    self.runID = runID
    self.suiteID = suiteID
    self.caseID = caseID
    self.iterationID = iterationID
    self.sampleID = sampleID
    self.spanID = spanID
    self.eventID = eventID
    self.metricID = metricID
    self.attachmentID = attachmentID
    self.rowID = rowID
    self.dimensionCurveID = dimensionCurveID
  }
}

enum ReportIDFactory {
  static func suite(_ name: String) -> ReportID {
    ReportID(rawValue: "suite:\(stable(name))")
  }

  static func benchmarkCase(suiteName: String, caseName: String) -> ReportID {
    ReportID(rawValue: "case:\(stable(suiteName)).\(stable(caseName))")
  }

  static func row(
    suiteName: String,
    caseName: String,
    size: Benchmark.Dimension.Size?
  ) -> ReportID {
    if let size {
      return ReportID(rawValue: "row:\(stable(suiteName)).\(stable(caseName)).size-\(size.rawValue)")
    }
    return ReportID(rawValue: "row:\(stable(suiteName)).\(stable(caseName))")
  }

  static func iteration(
    suiteName: String,
    caseName: String,
    size: Benchmark.Dimension.Size? = nil,
    iteration: Int
  ) -> ReportID {
    ReportID(
      rawValue: "iteration:\(stable(suiteName)).\(stable(caseName))\(dimensionSuffix(size)).\(iteration)"
    )
  }

  static func sample(
    suiteName: String,
    caseName: String,
    size: Benchmark.Dimension.Size? = nil,
    iteration: Int
  ) -> ReportID {
    ReportID(rawValue: "sample:\(stable(suiteName)).\(stable(caseName))\(dimensionSuffix(size)).\(iteration)")
  }

  static func dimensionCurve(
    suiteName: String,
    caseName: String,
    metric: Report.Measurement.Metric
  ) -> ReportID {
    ReportID(rawValue: "curve:\(stable(suiteName)).\(stable(caseName)).\(metric.rawValue)")
  }

  static func stable(_ value: String) -> String {
    value
      .lowercased()
      .map { character in
        character.isLetter || character.isNumber ? character : "-"
      }
      .reduce(into: "") { partial, character in
        if character == "-", partial.last == "-" {
          return
        }
        partial.append(character)
      }
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func dimensionSuffix(_ size: Benchmark.Dimension.Size?) -> String {
    guard let size else {
      return ""
    }
    return ".size-\(size.rawValue)"
  }
}
