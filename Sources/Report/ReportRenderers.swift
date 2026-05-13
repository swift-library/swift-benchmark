import Foundation

public enum JSONReportRenderer {
  public static func render(_ document: ReportDocument) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(document)
    return String(decoding: data, as: UTF8.self)
  }
}

public enum MarkdownReportRenderer {
  public static func render(_ document: ReportDocument) -> String {
    var lines: [String] = []
    lines.append("# Benchmark Report")
    lines.append("")
    lines.append("- Run: `\(document.metadata.id.rawValue)`")
    lines.append("- Schema: \(document.schemaVersion)")
    lines.append("- Verdict: `\(document.summary.verdict.rawValue)`")
    lines.append("- Suites: \(document.summary.suiteCount)")
    lines.append("- Cases: \(document.summary.caseCount)")
    lines.append("- Failed regressions: \(document.summary.failedRegressionCount)")
    lines.append("- Failed budgets: \(document.summary.failedBudgetCount)")
    lines.append("- Unavailable diagnostics: \(document.summary.unavailableDiagnosticCount)")
    lines.append("")

    for suite in document.suites {
      lines.append("## \(suite.name)")
      lines.append("")
      lines.append("| Case | Mean | Median | p95 | Baseline | Budgets | Verdict | Causes | Diagnostics |")
      lines.append("| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: |")
      for report in suite.cases {
        let baseline = report.baseline.map { formatNanoseconds($0.baselineMeanNanoseconds) } ?? "-"
        let failedBudgets = report.budgets.filter { $0.verdict == .failed }.count
        lines.append(
          "| \(report.name) | \(formatNanoseconds(report.metrics.mean)) | \(formatNanoseconds(report.metrics.median)) | \(formatNanoseconds(report.metrics.p95)) | \(baseline) | \(failedBudgets)/\(report.budgets.count) | \(report.verdict.rawValue) | \(report.verdictCauses.count) | \(report.diagnostics.count) |"
        )
      }
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }
}

public enum ConsoleReportRenderer {
  public static func render(_ document: ReportDocument) -> String {
    var lines: [String] = []
    lines.append("Benchmark Report \(document.metadata.id.rawValue)")
    lines.append("Schema: \(document.schemaVersion)")
    lines.append("Verdict: \(document.summary.verdict.rawValue)")
    for suite in document.suites {
      lines.append("")
      lines.append("[\(suite.name)]")
      for report in suite.cases {
        lines.append(
          "\(report.name): mean \(formatNanoseconds(report.metrics.mean)), p95 \(formatNanoseconds(report.metrics.p95)), budgets \(report.budgets.filter { $0.verdict == .failed }.count)/\(report.budgets.count), causes \(report.verdictCauses.count), verdict \(report.verdict.rawValue)"
        )
      }
    }
    return lines.joined(separator: "\n")
  }
}

func formatNanoseconds(_ value: Double) -> String {
  if value >= 1_000_000 {
    return String(format: "%.3f ms", value / 1_000_000)
  }
  if value >= 1_000 {
    return String(format: "%.3f us", value / 1_000)
  }
  return String(format: "%.0f ns", value)
}

public enum SpeedscopeReportRenderer {
  public static func render(_ document: ReportDocument) throws -> String {
    var builder = SpeedscopeBuilder()
    let file = builder.makeFile(document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(file)
    return String(decoding: data, as: UTF8.self)
  }
}

private struct SpeedscopeFile: Codable {
  var schema: String
  var shared: SpeedscopeShared
  var profiles: [SpeedscopeProfile]
  var activeProfileIndex: Int

  enum CodingKeys: String, CodingKey {
    case schema = "$schema"
    case shared
    case profiles
    case activeProfileIndex
  }
}

private struct SpeedscopeShared: Codable {
  var frames: [SpeedscopeFrame]
}

private struct SpeedscopeFrame: Codable {
  var name: String
}

private struct SpeedscopeProfile: Codable {
  var type: String
  var name: String
  var unit: String
  var startValue: UInt64
  var endValue: UInt64
  var events: [SpeedscopeEvent]
}

private struct SpeedscopeEvent: Codable {
  var type: String
  var frame: Int
  var at: UInt64
}

private struct SpeedscopeBuilder {
  private var frames: [SpeedscopeFrame] = []
  private var frameIndexes: [String: Int] = [:]

  mutating func makeFile(_ document: ReportDocument) -> SpeedscopeFile {
    var profiles: [SpeedscopeProfile] = []
    for suite in document.suites {
      for report in suite.cases {
        for attribution in report.attributions {
          let spans = attribution.spans.filter { $0.durationNanoseconds != nil && $0.endNanoseconds != nil }
          guard !spans.isEmpty else {
            continue
          }
          let minStart = spans.map(\.startNanoseconds).min() ?? 0
          let maxEnd = spans.compactMap(\.endNanoseconds).max() ?? minStart
          var events: [SpeedscopeEvent] = []
          for span in spans.sorted(by: { $0.startNanoseconds < $1.startNanoseconds }) {
            guard let end = span.endNanoseconds else {
              continue
            }
            let frame = frameIndex(for: span.name)
            events.append(SpeedscopeEvent(type: "O", frame: frame, at: span.startNanoseconds - minStart))
            events.append(SpeedscopeEvent(type: "C", frame: frame, at: end - minStart))
          }
          profiles.append(
            SpeedscopeProfile(
              type: "evented",
              name: profileName(suite: suite.name, report: report.name, attribution: attribution),
              unit: "nanoseconds",
              startValue: 0,
              endValue: maxEnd - minStart,
              events: events.sorted { lhs, rhs in
                if lhs.at == rhs.at {
                  return lhs.type == "C" && rhs.type == "O"
                }
                return lhs.at < rhs.at
              }
            )
          )
        }
      }
    }
    return SpeedscopeFile(
      schema: "https://www.speedscope.app/file-format-schema.json",
      shared: SpeedscopeShared(frames: frames),
      profiles: profiles,
      activeProfileIndex: 0
    )
  }

  private mutating func frameIndex(for name: String) -> Int {
    if let index = frameIndexes[name] {
      return index
    }
    let index = frames.count
    frameIndexes[name] = index
    frames.append(SpeedscopeFrame(name: name))
    return index
  }

  private func profileName(suite: String, report: String, attribution: TimelineAttribution) -> String {
    if let sampleID = attribution.scope.sampleID {
      return "\(suite).\(report) \(sampleID.rawValue)"
    }
    return "\(suite).\(report)"
  }
}
