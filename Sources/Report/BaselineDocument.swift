// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// The measurements a baseline file stores for one case.
public struct BaselineCase: Sendable, Equatable, Codable {
  /// The suite the case belongs to.
  public var suiteName: String
  /// The case's name.
  public var caseName: String
  /// The case's recorded samples and statistics.
  public var measurement: Report.Measurement

  /// Creates a baseline entry for one case.
  public init(suiteName: String, caseName: String, measurement: Report.Measurement) {
    self.suiteName = suiteName
    self.caseName = caseName
    self.measurement = measurement
  }
}

/// A baseline file: the measurements of an earlier run to compare with.
public struct BaselineDocument: Sendable, Equatable, Codable {
  /// The conditions the baseline was recorded under, compared with the run's.
  public var metadata: RunMetadata?
  public var cases: [BaselineCase]

  /// Creates a baseline from cases and the conditions they were recorded under.
  public init(metadata: RunMetadata? = nil, cases: [BaselineCase]) {
    self.metadata = metadata
    self.cases = cases
  }

  /// A baseline holding every case of `document`.
  public init(document: ReportDocument) {
    self.init(
      metadata: document.metadata,
      cases: document.suites.flatMap { suite in
        suite.cases.map { report in
          BaselineCase(
            suiteName: suite.name,
            caseName: report.name,
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

  /// Reads a baseline JSON file written by the `baseline write` command.
  package static func read(path: String) throws -> BaselineDocument {
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw BaselineReadError.unavailable(path: path, reason: error.localizedDescription)
    }
    do {
      return try JSONDecoder().decode(BaselineDocument.self, from: data)
    } catch is DecodingError {
      throw BaselineReadError.unreadable(path: path)
    }
  }
}

package enum BaselineReadError: Error, CustomStringConvertible, Equatable {
  case unavailable(path: String, reason: String)
  case unreadable(path: String)

  package var description: String {
    switch self {
    case .unavailable(let path, let reason):
      return "Cannot read baseline '\(path)': \(reason)"
    case .unreadable(let path):
      return
        "'\(path)' is not a baseline this swift-benchmark can read. Record it again with the baseline write command."
    }
  }
}
