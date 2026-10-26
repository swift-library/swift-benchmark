// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation

package enum JSONReportRenderer {
  package static func render(_ document: ReportDocument) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(document)
    return String(decoding: data, as: UTF8.self)
  }
}

package enum ConsoleReportRenderer {
  package static func render(_ document: ReportDocument) -> String {
    var lines: [String] = []
    lines.append("Benchmark Report \(document.metadata.id.rawValue)")
    lines.append("Verdict: \(document.summary.verdict.rawValue)")
    for warning in document.warnings {
      lines.append("Warning: \(warning.message)")
    }
    for suite in document.suites {
      lines.append("")
      lines.append("[\(suite.name)]")
      for report in suite.cases {
        let metrics = report.measurement.metrics.compactMap { metric -> String? in
          guard let statistics = report.measurement.statistics(for: metric) else {
            return nil
          }
          return
            "\(metric.name) median \(formatValue(statistics.median, unit: metric.unit)), p95 \(formatValue(statistics.p95, unit: metric.unit))"
        }
        let failedBudgets = report.budgets.filter { $0.verdict == .failed }.count
        lines.append(
          "\(report.name): \(metrics.joined(separator: "; ")); budgets \(failedBudgets)/\(report.budgets.count), causes \(report.verdictCauses.count), verdict \(report.verdict.rawValue)"
        )
        for warning in report.warnings {
          lines.append("  warning: \(warning.message)")
        }
        for row in report.measurement.rows {
          guard let sites = row.allocationSites else {
            continue
          }
          let rowPrefix = row.label.map { "\($0): " } ?? ""
          for stack in sites.stacks.prefix(3) {
            lines.append(
              "  \(rowPrefix)\(formatValue(stack.allocationsPerCall(of: sites), unit: .count)) allocations, \(formatValue(stack.bytesPerCall(of: sites), unit: .bytes)) per call at \(stack.summary())"
            )
          }
        }
      }
    }
    return lines.joined(separator: "\n")
  }
}

/// Formats a metric value with a human-readable unit suffix.
func formatValue(_ value: Double, unit: Benchmark.Metric.Unit) -> String {
  switch unit {
  case .nanoseconds:
    return formatNanoseconds(value)
  case .bytes:
    if abs(value) >= 1_048_576 {
      return String(format: "%.2f MiB", value / 1_048_576)
    }
    if abs(value) >= 1_024 {
      return String(format: "%.2f KiB", value / 1_024)
    }
    return String(format: "%.0f B", value)
  case .count:
    return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
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

package enum SpeedscopeReportRenderer {
  package static func render(_ document: ReportDocument) throws -> String {
    var builder = SpeedscopeBuilder()
    let file = builder.makeFile(document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(file)
    return String(decoding: data, as: UTF8.self)
  }
}

private struct SpeedscopeFile: Encodable {
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

private struct SpeedscopeShared: Encodable {
  var frames: [SpeedscopeFrame]
}

private struct SpeedscopeFrame: Encodable {
  var name: String
}

/// A timeline of spans, or call stacks weighted by allocations or bytes.
private enum SpeedscopeProfile: Encodable {
  case evented(SpeedscopeEventedProfile)
  case sampled(SpeedscopeSampledProfile)

  func encode(to encoder: any Encoder) throws {
    switch self {
    case .evented(let profile):
      try profile.encode(to: encoder)
    case .sampled(let profile):
      try profile.encode(to: encoder)
    }
  }
}

private struct SpeedscopeEventedProfile: Encodable {
  var type = "evented"
  var name: String
  var unit: String
  var startValue: UInt64
  var endValue: UInt64
  var events: [SpeedscopeEvent]
}

/// Stacks of frame indexes, outermost first, each with its weight.
private struct SpeedscopeSampledProfile: Encodable {
  var type = "sampled"
  var name: String
  var unit: String
  var startValue: Double = 0
  var endValue: Double
  var samples: [[Int]]
  var weights: [Double]
}

private struct SpeedscopeEvent: Encodable {
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
          let spans = attribution.spans.filter {
            $0.durationNanoseconds != nil && $0.endNanoseconds != nil
          }
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
            events.append(
              SpeedscopeEvent(type: "O", frame: frame, at: span.startNanoseconds - minStart))
            events.append(SpeedscopeEvent(type: "C", frame: frame, at: end - minStart))
          }
          profiles.append(
            .evented(
              SpeedscopeEventedProfile(
                name: profileName(
                  suite: suite.name, report: report.name, attribution: attribution),
                unit: "nanoseconds",
                startValue: 0,
                endValue: maxEnd - minStart,
                events: events.sorted { lhs, rhs in
                  if lhs.at == rhs.at {
                    return lhs.type == "C" && rhs.type == "O"
                  }
                  return lhs.at < rhs.at
                }
              ))
          )
        }
        for row in report.measurement.rows {
          guard let sites = row.allocationSites, !sites.stacks.isEmpty else {
            continue
          }
          let name = "\(suite.name).\(report.name)" + (row.label.map { " \($0)" } ?? "")
          let samples = sites.stacks.map { $0.frames.reversed().map { frameIndex(for: $0) } }
          for (kind, unit, weights) in [
            ("allocations", "none", sites.stacks.map { $0.allocationsPerCall(of: sites) }),
            ("allocated bytes", "bytes", sites.stacks.map { $0.bytesPerCall(of: sites) }),
          ] {
            profiles.append(
              .sampled(
                SpeedscopeSampledProfile(
                  name: "\(name) \(kind) per call",
                  unit: unit,
                  endValue: weights.reduce(0, +),
                  samples: samples,
                  weights: weights
                ))
            )
          }
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

  private func profileName(suite: String, report: String, attribution: TimelineAttribution)
    -> String
  {
    if let sampleID = attribution.scope.sampleID {
      return "\(suite).\(report) \(sampleID.rawValue)"
    }
    return "\(suite).\(report)"
  }
}

extension Benchmark.AllocationStack {
  /// Prefixes of frames inside the Swift runtime's allocation path and the
  /// system allocator, which every stack shares.
  private static let allocatorFramePrefixes = [
    "swift::", "swift_", "_swift_", "malloc", "_malloc", "calloc", "realloc", "operator new",
    "__libc_", "objc_", "_objc_",
  ]

  /// Up to `limit` frames, innermost first, starting at the innermost one
  /// outside the Swift runtime's allocation path and the system allocator.
  func summary(frames limit: Int = 2) -> String {
    let start =
      frames.firstIndex { frame in
        !Self.allocatorFramePrefixes.contains { frame.hasPrefix($0) }
      } ?? 0
    let shown = frames[start...].prefix(limit)
    return shown.isEmpty ? "(unknown)" : shown.joined(separator: " ← ")
  }

  func allocationsPerCall(of sites: Benchmark.AllocationSites) -> Double {
    Double(allocations) / Double(max(sites.calls, 1))
  }

  func bytesPerCall(of sites: Benchmark.AllocationSites) -> Double {
    Double(bytes) / Double(max(sites.calls, 1))
  }
}
