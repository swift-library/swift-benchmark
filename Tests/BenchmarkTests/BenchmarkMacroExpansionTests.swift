#if canImport(SwiftSyntaxMacrosTestSupport)
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

@testable import BenchmarkMacro

@Suite("Benchmark Macro Expansion")
struct BenchmarkMacroExpansionTests {
  private let macros: [String: Macro.Type] = [
    "BenchmarkSuite": BenchmarkSuiteMacro.self,
    "Benchmark": BenchmarkMacro.self,
  ]

  @Test
  func benchmarkSuiteLowersBenchmarkFunctionsIntoDiscoverySuites() {
    assertMacroExpansion(
      """
      @BenchmarkSuite("Parser")
      struct ParserBenchmarks {
        @Benchmark("Parse document")
        func parse() {
          blackHole(1)
        }
      }
      """,
      expandedSource: """
      struct ParserBenchmarks {
        @Benchmark("Parse document")
        func parse() {
          blackHole(1)
        }

        static var __benchmarkSuites: [BenchmarkSuite] {
          [
            BenchmarkSuite("Parser", traits: []) {
              Benchmark("Parse document", traits: []) {
                Self().parse()
              }
            }
          ]
        }
      }

      extension ParserBenchmarks: _BenchmarkDiscovery {
      }
      """,
      macros: macros
    )
  }

  @Test
  func benchmarkSuiteLowersTraitsIntoDiscoverySuites() {
    assertMacroExpansion(
      """
      @BenchmarkSuite("Parser", .tag("parser"), .configuration(.init(warmup: .none, iterations: .iterations(1))))
      struct ParserBenchmarks {
        @Benchmark("Parse document", .tag("fast"), .skip("disabled"))
        static func parse() async throws {
          blackHole(1)
        }
      }
      """,
      expandedSource: """
      struct ParserBenchmarks {
        @Benchmark("Parse document", .tag("fast"), .skip("disabled"))
        static func parse() async throws {
          blackHole(1)
        }

        static var __benchmarkSuites: [BenchmarkSuite] {
          [
            BenchmarkSuite("Parser", traits: [.tag("parser"), .configuration(.init(warmup: .none, iterations: .iterations(1)))]) {
              Benchmark("Parse document", traits: [.tag("fast"), .skip("disabled")]) {
                try await Self.parse()
              }
            }
          ]
        }
      }

      extension ParserBenchmarks: _BenchmarkDiscovery {
      }
      """,
      macros: macros
    )
  }

  @Test
  func benchmarkSuiteLowersArgumentsIntoDiscoverySuites() {
    assertMacroExpansion(
      """
      @BenchmarkSuite("Parser")
      struct ParserBenchmarks {
        @Benchmark("Parse", arguments: [1, 2])
        func parse(_ size: Int) {
          blackHole(size)
        }
      }
      """,
      expandedSource: """
      struct ParserBenchmarks {
        @Benchmark("Parse", arguments: [1, 2])
        func parse(_ size: Int) {
          blackHole(size)
        }

        static var __benchmarkSuites: [BenchmarkSuite] {
          [
            BenchmarkSuite("Parser", traits: []) {
              Benchmark("Parse", arguments: [1, 2], traits: []) { __benchmarkArgument0 in
                Self().parse(__benchmarkArgument0)
              }
            }
          ]
        }
      }

      extension ParserBenchmarks: _BenchmarkDiscovery {
      }
      """,
      macros: macros
    )
  }
}
#endif
