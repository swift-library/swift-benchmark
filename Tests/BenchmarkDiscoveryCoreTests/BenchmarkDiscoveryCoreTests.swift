import Foundation
import Testing
@testable import _BenchmarkDiscoveryCore

@Suite("Benchmark Discovery Core")
struct BenchmarkDiscoveryCoreTests {
  @Test
  func nativeBenchmarkSuiteDiscoveryBuildsPlanAndHostSource() throws {
    let directory = try temporaryDirectory()
    let source = directory.appendingPathComponent("LibraryBenchmarks.swift")
    try """
      import Benchmark

      @BenchmarkSuite("Parser")
      struct ParserBenchmarks {
        @Benchmark("Noop")
        func noop() {}
      }
      """
      .write(to: source, atomically: true, encoding: .utf8)

    let plan = try BenchmarkDiscoveryPlanner(
      manifest: TargetManifest(
        targets: [
          TargetDescription(
            name: "FixtureLibrary",
            moduleName: "FixtureLibrary",
            kind: "library",
            sourcePaths: [source.path]
          )
        ]
      ),
      workDirectory: directory
    ).makePlan()

    #expect(plan.nativeDiscoveries.count == 1)
    #expect(plan.nativeDiscoveries[0].discoveryTypeName == "__BenchmarkDiscovery_ParserBenchmarks")
    #expect(plan.discoveryExpressions == ["FixtureLibrary.__BenchmarkDiscovery_ParserBenchmarks.self"])
    #expect(plan.discoveredTargetNames == ["FixtureLibrary"])
    #expect(plan.requiresSwiftTesting == false)

    let hostSource = try String(contentsOfFile: plan.generatedHostSourcePath, encoding: .utf8)
    #expect(hostSource.contains("import FixtureLibrary"))
    #expect(hostSource.contains("FixtureLibrary.__BenchmarkDiscovery_ParserBenchmarks.self"))

    let repeatedPlan = try BenchmarkDiscoveryPlanner(
      manifest: TargetManifest(
        targets: [
          TargetDescription(
            name: "FixtureLibrary",
            moduleName: "FixtureLibrary",
            kind: "library",
            sourcePaths: [source.path]
          )
        ]
      ),
      workDirectory: directory
    ).makePlan()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try encoder.encode(plan) == encoder.encode(repeatedPlan))
  }

  @Test
  func testingBridgeDiscoveryBuildsBridgeSourceAndSkipsPlainTests() throws {
    let directory = try temporaryDirectory()
    let source = directory.appendingPathComponent("TestingBenchmarks.swift")
    try """
      import Benchmark
      import BenchmarkTesting
      import Testing

      extension Tag {
        @Tag static var testingBridge: Self
      }

      @Suite(
        "TestingFixture",
        .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
        .tags(.testingBridge)
      )
      struct FixtureBenchmarkTestingSuite {
        @Test("Suite Noop")
        func suiteNoop() {
          blackHole(3)
        }
      }

      struct StandaloneTestingBenchmarks {
        @Test(
          "Standalone Testing Benchmark",
          .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1)))
        )
        func standalone() {
          blackHole(4)
        }

        @Test("Plain Test")
        func plainTestIsNotBenchmark() {
          blackHole(5)
        }
      }
      """
      .write(to: source, atomically: true, encoding: .utf8)

    let plan = try BenchmarkDiscoveryPlanner(
      manifest: TargetManifest(
        targets: [
          TargetDescription(
            name: "FixtureBenchmarkTests",
            moduleName: "FixtureBenchmarkTests",
            kind: "test",
            sourcePaths: [source.path]
          )
        ]
      ),
      workDirectory: directory
    ).makePlan()

    #expect(plan.nativeDiscoveries.isEmpty)
    #expect(plan.testingBridges.count == 1)
    #expect(plan.requiresSwiftTesting)
    #expect(plan.discoveryExpressions == ["__BenchmarkTestingDiscovery_FixtureBenchmarkTests.self"])

    let bridgeSource = try String(
      contentsOfFile: plan.testingBridges[0].sourcePath,
      encoding: .utf8
    )
    #expect(bridgeSource.contains("@testable import FixtureBenchmarkTests"))
    #expect(bridgeSource.contains("TestingFixture"))
    #expect(bridgeSource.contains("Suite Noop"))
    #expect(bridgeSource.contains("Standalone Testing Benchmark"))
    #expect(!bridgeSource.contains("Plain Test"))
  }

  @Test
  func testingBridgeReportsPrivateAndArgumentsDiagnostics() throws {
    let directory = try temporaryDirectory()
    let source = directory.appendingPathComponent("InvalidTestingBenchmarks.swift")
    try """
      import BenchmarkTesting
      import Testing

      @Suite(.benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))))
      struct InvalidTestingBenchmarks {
        @Test("Private")
        private func privateBenchmark() {}

        @Test("Arguments", arguments: [1, 2])
        func argumentBenchmark(_ value: Int) {}
      }
      """
      .write(to: source, atomically: true, encoding: .utf8)

    do {
      _ = try BenchmarkDiscoveryPlanner(
        manifest: TargetManifest(
          targets: [
            TargetDescription(
              name: "InvalidTests",
              moduleName: "InvalidTests",
              kind: "test",
              sourcePaths: [source.path]
            )
          ]
        ),
        workDirectory: directory
      ).makePlan()
      Issue.record("Expected benchmark testing diagnostics")
    } catch {
      let message = String(describing: error)
      #expect(message.contains("private/fileprivate @Test(.benchmark) cannot be bridged"))
      #expect(message.contains("@Test(arguments:) is not mapped to Benchmark.Dimension"))
    }
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-discovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
