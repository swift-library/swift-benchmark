import Foundation
import Testing
@testable import _BenchmarkDiscoveryCore
@testable import _BenchmarkSyntaxDiscoveryCore

@Suite("Benchmark Syntax Discovery Core")
struct BenchmarkSyntaxDiscoveryCoreTests {
  @Test
  func syntaxNativeDiscoveryMatchesStablePlanForSimpleSuite() throws {
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
    let manifest = TargetManifest(
      targets: [
        TargetDescription(
          name: "FixtureLibrary",
          moduleName: "FixtureLibrary",
          kind: "library",
          sourcePaths: [source.path]
        )
      ]
    )

    let stablePlan = try BenchmarkDiscoveryPlanner(
      manifest: manifest,
      workDirectory: directory.appendingPathComponent("stable")
    ).makePlan()
    let syntaxPlan = try SyntaxDiscoveryPlanner(
      manifest: manifest,
      workDirectory: directory.appendingPathComponent("syntax")
    ).makePlan()

    #expect(syntaxPlan.nativeDiscoveries == stablePlan.nativeDiscoveries)
    #expect(syntaxPlan.discoveryExpressions == stablePlan.discoveryExpressions)
    #expect(syntaxPlan.discoveredTargetNames == stablePlan.discoveredTargetNames)
    #expect(syntaxPlan.requiresSwiftTesting == stablePlan.requiresSwiftTesting)
  }

  @Test
  func syntaxTestingBridgeMatchesStableBridgeSemantics() throws {
    let directory = try temporaryDirectory()
    let source = directory.appendingPathComponent("TestingBenchmarks.swift")
    try """
      import Benchmark
      import BenchmarkTesting
      import Testing

      extension Tag {
        @Tag static var parser: Self
      }

      @Suite(
        "TestingFixture",
        .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
        .tags(.parser)
      )
      struct FixtureBenchmarkTestingSuite {
        @Test("Suite Noop")
        func suiteNoop() {
          blackHole(3)
        }

        @Benchmark("Suite Native Arguments", arguments: [1, 2])
        func suiteNativeArguments(_ value: Int) {
          blackHole(value)
        }

        @Test(
          "Case Override",
          .benchmark(configuration: .init(warmup: .none, iterations: .iterations(2)))
        )
        func caseOverride() {
          blackHole(4)
        }
      }

      struct StandaloneTestingBenchmarks {
        @Test(
          "Standalone",
          .benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))),
          .tags("standalone")
        )
        func standalone() {
          blackHole(5)
        }

        @Test("Plain Test")
        func plain() {
          blackHole(6)
        }
      }
      """
      .write(to: source, atomically: true, encoding: .utf8)
    let manifest = TargetManifest(
      targets: [
        TargetDescription(
          name: "FixtureBenchmarkTests",
          moduleName: "FixtureBenchmarkTests",
          kind: "test",
          sourcePaths: [source.path]
        )
      ]
    )

    let stablePlan = try BenchmarkDiscoveryPlanner(
      manifest: manifest,
      workDirectory: directory.appendingPathComponent("stable")
    ).makePlan()
    let syntaxPlan = try SyntaxDiscoveryPlanner(
      manifest: manifest,
      workDirectory: directory.appendingPathComponent("syntax")
    ).makePlan()

    #expect(syntaxPlan.nativeDiscoveries == stablePlan.nativeDiscoveries)
    #expect(syntaxPlan.discoveryExpressions == stablePlan.discoveryExpressions)
    #expect(syntaxPlan.discoveredTargetNames == stablePlan.discoveredTargetNames)
    #expect(syntaxPlan.requiresSwiftTesting == stablePlan.requiresSwiftTesting)

    let bridgeSource = try String(
      contentsOfFile: syntaxPlan.testingBridges[0].sourcePath,
      encoding: .utf8
    )
    #expect(bridgeSource.contains("TestingFixture"))
    #expect(bridgeSource.contains("Suite Noop"))
    #expect(bridgeSource.contains("Suite Native Arguments"))
    #expect(bridgeSource.contains("arguments: [1, 2]"))
    #expect(bridgeSource.contains("Case Override"))
    #expect(bridgeSource.contains("Standalone"))
    #expect(bridgeSource.contains(".tag(\"parser\")"))
    #expect(bridgeSource.contains(".tag(\"standalone\")"))
    #expect(!bridgeSource.contains("Plain Test"))
  }

  @Test
  func syntaxScannerIgnoresCommentsAndStringLiterals() throws {
    let directory = try temporaryDirectory()
    let source = directory.appendingPathComponent("LibraryBenchmarks.swift")
    try #"""
      import Benchmark

      // @BenchmarkSuite("Fake")
      let text = "@BenchmarkSuite(\"StringLiteral\") struct Fake {}"

      @BenchmarkSuite(
        "Real"
      )
      struct RealBenchmarks {
        @Benchmark("Noop")
        func noop() {}
      }
      """#
      .write(to: source, atomically: true, encoding: .utf8)

    let plan = try SyntaxDiscoveryPlanner(
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

    #expect(plan.nativeDiscoveries.map(\.typeName) == ["RealBenchmarks"])
  }

  @Test
  func syntaxScannerPreservesNestedNativeDiscoveryPath() throws {
    let directory = try temporaryDirectory()
    let source = directory.appendingPathComponent("NestedBenchmarks.swift")
    try """
      import Benchmark

      enum Outer {
        @BenchmarkSuite("Nested")
        struct InnerBenchmarks {
          @Benchmark("Noop")
          func noop() {}
        }
      }
      """
      .write(to: source, atomically: true, encoding: .utf8)

    let plan = try SyntaxDiscoveryPlanner(
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

    #expect(plan.nativeDiscoveries[0].typeName == "Outer.InnerBenchmarks")
    #expect(plan.discoveryExpressions == [
      "FixtureLibrary.Outer.__BenchmarkDiscovery_InnerBenchmarks.self"
    ])
  }

  @Test
  func syntaxTestingBridgeReportsPrivateDiagnosticsAndAcceptsArguments() throws {
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
      _ = try SyntaxDiscoveryPlanner(
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
      Issue.record("Expected syntax discovery diagnostics")
    } catch {
      let message = String(describing: error)
      #expect(message.contains("private/fileprivate benchmark declarations cannot be bridged"))
      #expect(!message.contains("@Test(arguments:) is not mapped to Benchmark.Dimension"))
    }

    let validDirectory = try temporaryDirectory()
    let validSource = validDirectory.appendingPathComponent("ArgumentBenchmarks.swift")
    try """
      import BenchmarkTesting
      import Testing

      @Suite(.benchmark(configuration: .init(warmup: .none, iterations: .iterations(1))))
      struct ArgumentBenchmarks {
        @Test("Arguments", arguments: [1, 2])
        func argumentBenchmark(_ value: Int) {}
      }
      """
      .write(to: validSource, atomically: true, encoding: .utf8)

    let plan = try SyntaxDiscoveryPlanner(
      manifest: TargetManifest(
        targets: [
          TargetDescription(
            name: "ArgumentTests",
            moduleName: "ArgumentTests",
            kind: "test",
            sourcePaths: [validSource.path]
          )
        ]
      ),
      workDirectory: validDirectory
    ).makePlan()
    let bridgeSource = try String(contentsOfFile: plan.testingBridges[0].sourcePath, encoding: .utf8)
    #expect(bridgeSource.contains("arguments: [1, 2]"))
    #expect(bridgeSource.contains("__benchmarkArgument0"))
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-syntax-discovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
