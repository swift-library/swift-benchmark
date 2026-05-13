import Benchmark
import Report
import Testing

@Suite("Report Measurement")
struct ReportMeasurementTests {
  @Test
  func metricsAreComputedFromSamples() {
    let metrics = Report.Measurement.Metrics(
      samples: [
        SampleReport(
          id: "sample:metrics.0",
          iterationID: "iteration:metrics.0",
          iteration: 0,
          durationNanoseconds: 10
        ),
        SampleReport(
          id: "sample:metrics.1",
          iterationID: "iteration:metrics.1",
          iteration: 1,
          durationNanoseconds: 20
        ),
        SampleReport(
          id: "sample:metrics.2",
          iterationID: "iteration:metrics.2",
          iteration: 2,
          durationNanoseconds: 30
        ),
        SampleReport(
          id: "sample:metrics.3",
          iterationID: "iteration:metrics.3",
          iteration: 3,
          durationNanoseconds: 40
        ),
      ]
    )

    #expect(metrics.count == 4)
    #expect(metrics.min == 10)
    #expect(metrics.max == 40)
    #expect(metrics.mean == 25)
    #expect(metrics.median == 25)
    #expect(metrics.p90 == 37)
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
              size: Benchmark.Dimension.Size(10),
              samples: [
                Sample(iteration: 0, durationNanoseconds: 10),
                Sample(iteration: 1, durationNanoseconds: 20),
              ]
            ),
            Measurement.Row(
              size: Benchmark.Dimension.Size(100),
              samples: [
                Sample(iteration: 0, durationNanoseconds: 100),
                Sample(iteration: 1, durationNanoseconds: 200),
              ]
            ),
          ])
        )
      ]
    )

    let report = try #require(document.suites.first?.cases.first)
    let p95Curve = try #require(report.dimensionCurves.first { $0.metric == .p95 })

    #expect(report.measurement.rows.map(\.size?.rawValue) == [10, 100])
    #expect(report.measurement.rows.map(\.metrics.mean) == [15, 150])
    #expect(report.measurement.rows.map(\.amortized?.mean) == [1.5, 1.5])
    #expect(p95Curve.points.map(\.size.rawValue) == [10, 100])
    #expect(p95Curve.points.map(\.valueNanoseconds) == [19.5, 195])
    #expect(p95Curve.points.map(\.amortizedNanosecondsPerUnit) == [1.95, 1.95])
    #expect(p95Curve.points.first?.sourceLocation?.fileID == "DimensionTests/DimensionTests.swift")
  }
}
