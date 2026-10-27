// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import MacroTesting
import SwiftSyntaxMacros
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
          func parse() {
            blackHole(1)
          }

          public static var __benchmarkSuites: [BenchmarkSuite] {
            [
              BenchmarkSuite("Parser", traits: []) {
              Benchmark("Parse document", traits: []) {
                Self().parse()
              }
                }
            ]
          }
        }

        public enum __BenchmarkDiscovery_ParserBenchmarks: _BenchmarkDiscovery {
          public static var __benchmarkSuites: [BenchmarkSuite] {
            ParserBenchmarks.__benchmarkSuites
          }
        }

        extension ParserBenchmarks: _BenchmarkDiscovery {
        }
        """,
      macros: macros
    )
  }

  // `sort` writes `inout` and its type on separate lines, because setup
  // recognizes the parameter from the syntax tree, not from its text.
  @Test
  func benchmarkSuiteLowersSetupIntoPerCallInputs() {
    assertMacroExpansion(
      """
      @BenchmarkSuite("Sorting")
      struct SortingBenchmarks {
        @Benchmark("Sort", setup: Self.shuffled)
        func sort(_ values: inout
          [Int]) {
          values.sort()
        }

        @Benchmark("Sort sized", .dimension(sizes: [10, 100]), setup: Self.shuffled(_:))
        static func sortSized(values: inout [Int]) throws {
          values.sort()
        }
      }
      """,
      expandedSource: """

        struct SortingBenchmarks {
          func sort(_ values: inout
            [Int]) {
            values.sort()
          }
          static func sortSized(values: inout [Int]) throws {
            values.sort()
          }

          public static var __benchmarkSuites: [BenchmarkSuite] {
            [
              BenchmarkSuite("Sorting", traits: []) {
              Benchmark("Sort", traits: [], setup: Self.shuffled) { values in
                Self().sort(&values)
              }
              Benchmark("Sort sized", dimension: Benchmark.Dimension(sizes: [10, 100]), traits: [.dimension(sizes: [10, 100])], setup: Self.shuffled(_:)) { values in
                try Self.sortSized(values: &values)
              }
                }
            ]
          }
        }

        public enum __BenchmarkDiscovery_SortingBenchmarks: _BenchmarkDiscovery {
          public static var __benchmarkSuites: [BenchmarkSuite] {
            SortingBenchmarks.__benchmarkSuites
          }
        }

        extension SortingBenchmarks: _BenchmarkDiscovery {
        }
        """,
      macros: macros
    )
  }

  @Test
  func setupWithoutOneInoutParameterIsAnError() {
    assertMacroExpansion(
      """
      @BenchmarkSuite("Sorting")
      struct SortingBenchmarks {
        @Benchmark("Sort", setup: Self.shuffled)
        func sort(_ values: [Int]) {}
      }
      """,
      expandedSource: """

        struct SortingBenchmarks {
          func sort(_ values: [Int]) {}

          public static var __benchmarkSuites: [BenchmarkSuite] {
            [
              BenchmarkSuite("Sorting", traits: []) {
              }
            ]
          }
        }

        public enum __BenchmarkDiscovery_SortingBenchmarks: _BenchmarkDiscovery {
          public static var __benchmarkSuites: [BenchmarkSuite] {
            SortingBenchmarks.__benchmarkSuites
          }
        }

        extension SortingBenchmarks: _BenchmarkDiscovery {
        }
        """,
      diagnostics: [
        MacroDiagnostic(
          message: "@Benchmark 'sort' with setup: must take its input as one inout parameter.",
          line: 3, column: 3)
      ],
      macros: macros
    )
  }

  @Test
  func setupCannotCombineWithArguments() {
    assertMacroExpansion(
      """
      @BenchmarkSuite("Sorting")
      struct SortingBenchmarks {
        @Benchmark("Sort", setup: Self.shuffled, arguments: [1, 2])
        func sort(_ values: inout [Int]) {}
      }
      """,
      expandedSource: """

        struct SortingBenchmarks {
          func sort(_ values: inout [Int]) {}

          public static var __benchmarkSuites: [BenchmarkSuite] {
            [
              BenchmarkSuite("Sorting", traits: []) {
              }
            ]
          }
        }

        public enum __BenchmarkDiscovery_SortingBenchmarks: _BenchmarkDiscovery {
          public static var __benchmarkSuites: [BenchmarkSuite] {
            SortingBenchmarks.__benchmarkSuites
          }
        }

        extension SortingBenchmarks: _BenchmarkDiscovery {
        }
        """,
      diagnostics: [
        MacroDiagnostic(
          message: "@Benchmark 'sort' cannot combine setup: with arguments:.", line: 3, column: 3)
      ],
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
          static func parse() async throws {
            blackHole(1)
          }

          public static var __benchmarkSuites: [BenchmarkSuite] {
            [
              BenchmarkSuite("Parser", traits: [.tag("parser"), .configuration(.init(warmup: .none, iterations: .iterations(1)))]) {
              Benchmark("Parse document", traits: [.tag("fast"), .skip("disabled")]) {
                try await Self.parse()
              }
                }
            ]
          }
        }

        public enum __BenchmarkDiscovery_ParserBenchmarks: _BenchmarkDiscovery {
          public static var __benchmarkSuites: [BenchmarkSuite] {
            ParserBenchmarks.__benchmarkSuites
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
          func parse(_ size: Int) {
            blackHole(size)
          }

          public static var __benchmarkSuites: [BenchmarkSuite] {
            [
              BenchmarkSuite("Parser", traits: []) {
              Benchmark("Parse", arguments: [1, 2], traits: []) { __benchmarkArgument0 in
                Self().parse(__benchmarkArgument0)
              }
                }
            ]
          }
        }

        public enum __BenchmarkDiscovery_ParserBenchmarks: _BenchmarkDiscovery {
          public static var __benchmarkSuites: [BenchmarkSuite] {
            ParserBenchmarks.__benchmarkSuites
          }
        }

        extension ParserBenchmarks: _BenchmarkDiscovery {
        }
        """,
      macros: macros
    )
  }
}
