// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report
import Testing

@Suite("Report Measurement")
struct ReportMeasurementTests {
  @Test
  func statisticsAreComputedPerMetricFromSamples() throws {
    let allocations = Benchmark.Metric(name: "allocations", unit: .count)
    let samples = [10.0, 20, 30, 40].enumerated().map { index, wallClock in
      SampleReport(
        id: ReportID(rawValue: "sample:metrics.\(index)"),
        iterationID: ReportID(rawValue: "iteration:metrics.\(index)"),
        iteration: index,
        values: index == 0
          ? ["wallClock": wallClock] : ["wallClock": wallClock, "allocations": 3]
      )
    }
    let measurement = Report.Measurement(
      samples: samples, metrics: [.wallClock, allocations])

    let wallClock = try #require(measurement.statistics(for: .wallClock))
    #expect(wallClock.count == 4)
    #expect(wallClock.min == 10)
    #expect(wallClock.max == 40)
    #expect(wallClock.mean == 25)
    #expect(wallClock.median == 25)
    #expect(wallClock.p90 == 37)
    #expect(measurement.statistics(for: allocations)?.count == 3)
    #expect(measurement.metrics.map(\.name) == ["allocations", "wallClock"])
  }

  @Test
  func rowRecomputesStatisticsWhenDecoded() throws {
    let row = Report.Measurement.Row(
      size: Benchmark.Scale(4),
      samples: [
        SampleReport(
          id: "sample:row.0", iterationID: "iteration:row.0", iteration: 0,
          batchSize: 8, values: ["wallClock": 40])
      ],
      metrics: [.wallClock]
    )

    let decoded = try JSONDecoder().decode(
      Report.Measurement.Row.self, from: try JSONEncoder().encode(row))

    #expect(decoded == row)
    #expect(decoded.samples.first?.batchSize == 8)
    #expect(decoded.amortized?["wallClock"]?.mean == 10)
  }

  @Test
  func dimensionCurveIsDerivedFromMeasurementRows() throws {
    let document = ReportDocument(
      metadata: RunMetadata(
        id: "run:dimension",
        swiftVersion: "6.3.1",
        packageIdentity: "swift-benchmark",
        platform: "macOS",
        architecture: "arm64",
        osVersion: "15",
        generatedAt: "2026-05-11T00:00:00Z",
        buildConfiguration: "debug"
      ),
      results: [
        BenchmarkResult(
          suiteName: "Arrays",
          caseName: "Append",
          sourceLocation: BenchmarkSourceLocation(
            fileID: "DimensionTests/DimensionTests.swift",
            filePath: "/tmp/DimensionTests.swift",
            line: 10,
            column: 5
          ),
          configuration: .default,
          measurement: Measurement(rows: [
            Measurement.Row(
              size: Benchmark.Scale(10),
              samples: [
                Sample(iteration: 0, values: [.wallClock: 10]),
                Sample(iteration: 1, values: [.wallClock: 20]),
              ]
            ),
            Measurement.Row(
              size: Benchmark.Scale(100),
              samples: [
                Sample(iteration: 0, values: [.wallClock: 100]),
                Sample(iteration: 1, values: [.wallClock: 200]),
              ]
            ),
          ])
        )
      ]
    )

    let report = try #require(document.suites.first?.cases.first)
    let p95Curve = try #require(
      report.dimensionCurves.first { $0.metric == .wallClock && $0.statistic == .p95 })

    #expect(report.measurement.rows.map(\.size?.rawValue) == [10, 100])
    #expect(report.measurement.rows.map { $0.statistics(for: .wallClock)?.mean } == [15, 150])
    #expect(report.measurement.rows.map { $0.amortized?["wallClock"]?.mean } == [1.5, 1.5])
    #expect(p95Curve.points.map(\.size.rawValue) == [10, 100])
    #expect(p95Curve.points.map(\.value) == [19.5, 195])
    #expect(p95Curve.points.map(\.amortizedPerUnit) == [1.95, 1.95])
    #expect(p95Curve.points.first?.sourceLocation?.fileID == "DimensionTests/DimensionTests.swift")
  }
}
