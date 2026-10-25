// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Testing

@testable import _BenchmarkDiscoveryCore

@Suite("Testing Bridge")
struct TestingBridgeTests {
  @Test
  func enrolledDeclarationsBecomeBenchmarksAndPlainTestsDoNot() throws {
    let fixture = try DiscoveryFixture()
    let tests = try fixture.target(
      "FixtureBenchmarkTests", kind: "test",
      files: [
        "TestingBenchmarks.swift": """
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
      ])

    let plan = try fixture.plan(tests)
    let suites = try SourceScanner(target: tests).scan().suites

    #expect(plan.nativeDiscoveries.isEmpty)
    #expect(plan.requiresSwiftTesting)
    #expect(plan.discoveryExpressions == ["__BenchmarkTestingDiscovery_FixtureBenchmarkTests.self"])
    #expect(suites.map(\.name) == ["TestingFixture", "StandaloneTestingBenchmarks"])
    #expect(
      suites[0].traits == [
        ".configuration(.init(warmup: .none, iterations: .iterations(1)))", #".tag("parser")"#,
      ])
    #expect(
      suites[0].cases.map(\.name) == ["Suite Noop", "Suite Native Arguments", "Case Override"])
    #expect(suites[0].cases[1].argumentExpressions == ["[1, 2]"])
    #expect(
      suites[0].cases[2].traits == [
        ".configuration(.init(warmup: .none, iterations: .iterations(2)))"
      ])
    #expect(suites[1].cases.map(\.name) == ["Standalone"])
    #expect(suites[1].cases[0].traits.last == #".tag("standalone")"#)

    let bridgeSource = try String(
      contentsOfFile: plan.testingBridges[0].sourcePath, encoding: .utf8)
    #expect(bridgeSource.contains("@testable import FixtureBenchmarkTests"))
    #expect(bridgeSource.contains("let suite = FixtureBenchmarkTestingSuite()"))
    #expect(!bridgeSource.contains("Plain Test"))
  }

  @Test
  func attributesWrittenOnTheFunctionsLineAreFound() throws {
    let suites = try DiscoveryFixture().bridgedSuites(
      """
      import BenchmarkTesting
      import Testing

      struct Inline {
        @Test(.benchmark()) func inline() {}
        @Test("Named", .benchmark()) static func named() {}
      }
      """)

    #expect(suites.first?.cases.map(\.name) == ["inline", "Named"])
    #expect(suites.first?.cases.last?.invocation == "Inline.named()")
  }

  @Test
  func onlyALeadingStringLiteralNamesADeclaration() throws {
    let suites = try DiscoveryFixture().bridgedSuites(
      """
      import BenchmarkTesting
      import Testing

      struct Naming {
        @Test(.benchmark(), .tags("fast"))
        func tagged() {}

        @Test("benchmark(not a trait)")
        func plain() {}
      }
      """)

    #expect(suites.flatMap(\.cases).map(\.name) == ["tagged"])
    #expect(suites.first?.cases.first?.traits == [#".tag("fast")"#])
  }

  @Test
  func extensionMembersJoinTheirTypesSuite() throws {
    let fixture = try DiscoveryFixture()
    let tests = try fixture.target(
      "FixtureTests", kind: "test",
      files: [
        "Parser.swift": """
        import BenchmarkTesting
        import Testing

        @Suite("Parser", .benchmark())
        struct ParserTests {
          @Test func tokens() {}
        }
        """,
        "Parser+More.swift": """
        import Testing

        extension ParserTests {
          @Test func lines() async throws {}
          @Test mutating func reset() {}
        }
        """,
      ])

    let suites = try SourceScanner(target: tests).scan().suites

    #expect(suites.map(\.name) == ["Parser"])
    #expect(suites.first?.cases.map(\.name) == ["tokens", "lines", "reset"])
    #expect(
      suites.first?.cases[1].invocation == "let suite = ParserTests()\ntry await suite.lines()")
    #expect(suites.first?.cases[2].invocation == "var suite = ParserTests()\nsuite.reset()")
  }

  @Test
  func extensionsOfTypesFromOtherTargetsAreDiagnosed() throws {
    #expect {
      try DiscoveryFixture().plan(
        DiscoveryFixture().target(
          "FixtureTests", kind: "test",
          files: [
            "Tests.swift": """
            import BenchmarkTesting
            import Testing

            extension String {
              @Test(.benchmark()) func count() {}
              @Test func plain() {}
            }
            """
          ]))
    } throws: { error in
      String(describing: error).contains(
        "benchmark declarations in an extension of `String` need the type to be declared in the same target"
      )
    }
  }

  @Test
  func privateDeclarationsAndTypesAreDiagnosed() throws {
    let fixture = try DiscoveryFixture()
    let tests = try fixture.target(
      "InvalidTests", kind: "test",
      files: [
        "InvalidTestingBenchmarks.swift": """
        import BenchmarkTesting
        import Testing

        @Suite(.benchmark())
        struct InvalidTestingBenchmarks {
          @Test("Private")
          private func privateBenchmark() {}

          @Test("Arguments", arguments: [1, 2])
          func argumentBenchmark(_ value: Int) {}
        }

        @Suite(.benchmark())
        private struct HiddenBenchmarks {
          @Test func hidden() {}
        }
        """
      ])

    let diagnostics = try SourceScanner(target: tests).scan().diagnostics

    #expect(diagnostics.count == 2)
    #expect(diagnostics[0].contains("private/fileprivate benchmark declarations cannot be bridged"))
    #expect(diagnostics[1].contains("benchmark declarations in private/fileprivate types"))
  }

  @Test
  func argumentRowsBindToTheFunctionsParameters() throws {
    let suites = try DiscoveryFixture().bridgedSuites(
      """
      import BenchmarkTesting
      import Testing

      @Suite(.benchmark())
      struct ArgumentBenchmarks {
        @Test("One", arguments: [1, 2])
        func one(_ value: Int) {}

        @Test("Two", arguments: [1, 2], ["a"])
        func two(count: Int, label: String) {}

        @Test("Zipped", arguments: zip([1, 2], ["a", "b"]))
        func zipped(_ count: Int, _ label: String) {}
      }
      """)
    let cases = try #require(suites.first?.cases)

    #expect(
      cases.map(\.closureParameters) == [
        ["__benchmarkArgument0"],
        ["__benchmarkArgument0", "__benchmarkArgument1"],
        ["__benchmarkArgument0", "__benchmarkArgument1"],
      ])
    #expect(cases[1].argumentExpressions == ["[1, 2]", #"["a"]"#])
    #expect(
      cases[1].invocation.hasSuffix(
        "suite.two(count: __benchmarkArgument0, label: __benchmarkArgument1)"))
  }

  @Test
  func benchmarkTraitsAreForwardedAndDimensionsBecomeTheDimension() throws {
    let suites = try DiscoveryFixture().bridgedSuites(
      """
      import Benchmark
      import Testing

      struct SizedBenchmarks {
        @Benchmark("Sized", .dimension(sizes: [1, 2]), .tag("io"))
        static func sized(_ size: Benchmark.Scale) {}
      }
      """)
    let sized = try #require(suites.first?.cases.first)

    #expect(sized.dimensionExpression == "Benchmark.Dimension(sizes: [1, 2])")
    #expect(sized.traits == [#".tag("io")"#])
    #expect(sized.invocation == "SizedBenchmarks.sized(__benchmarkScale)")
  }
}
