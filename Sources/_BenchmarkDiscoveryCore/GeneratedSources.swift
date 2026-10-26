// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation

/// A benchmark suite the bridge declares for a Swift Testing suite, or for a
/// target's free functions.
struct DiscoveredSuite: Equatable {
  var name: String
  /// Benchmark suite trait expressions, as source.
  var traits: [String]
  var cases: [DiscoveredCase]
}

struct DiscoveredCase: Equatable {
  var name: String
  /// Benchmark case trait expressions, as source.
  var traits: [String]
  var sourceLocation: BenchmarkSourceLocationLiteral
  /// The `arguments:` collections, as source.
  var argumentExpressions: [String] = []
  /// The closure parameters the invocation refers to for one argument row.
  var closureParameters: [String] = []
  /// A `Benchmark.Dimension(...)` expression for Dimension cases.
  var dimensionExpression: String? = nil
  /// The statements that call the declared function.
  var invocation: String
}

struct BenchmarkSourceLocationLiteral: Equatable {
  var fileID: String
  var filePath: String
  var line: Int
  var column: Int

  var rendered: String {
    "BenchmarkSourceLocation(fileID: \(String(reflecting: fileID)), filePath: \(String(reflecting: filePath)), line: \(line), column: \(column))"
  }
}

/// Renders a test target's bridge: one discovery type listing the discovered
/// suites, compiled into the host with `@testable` access to the target.
struct BridgeSourceGenerator {
  var moduleName: String
  var discoveryName: String
  var suites: [DiscoveredSuite]

  func render() -> String {
    """
    import Benchmark
    import BenchmarkTesting
    import Report
    import Testing
    @testable import \(moduleName)

    enum \(discoveryName): _BenchmarkDiscovery {
      static var __benchmarkSuites: [BenchmarkSuite] {
        [
    \(suites.map(renderSuite).joined(separator: ",\n"))
        ]
      }
    }
    """
  }

  private func renderSuite(_ suite: DiscoveredSuite) -> String {
    """
          BenchmarkSuite(\(String(reflecting: suite.name)), traits: \(renderTraits(suite.traits))) {
    \(suite.cases.map(renderCase).joined(separator: "\n"))
          }
    """
  }

  private func renderCase(_ benchmarkCase: DiscoveredCase) -> String {
    if !benchmarkCase.argumentExpressions.isEmpty {
      return """
                Benchmark(
                  \(String(reflecting: benchmarkCase.name)),
                  arguments: \(benchmarkCase.argumentExpressions.joined(separator: ", ")),
                  traits: \(renderTraits(benchmarkCase.traits)),
                  sourceLocation: \(benchmarkCase.sourceLocation.rendered)
                ) { \(benchmarkCase.closureParameters.joined(separator: ", ")) in
        \(indent(benchmarkCase.invocation, spaces: 10))
                }
        """
    }
    if let dimension = benchmarkCase.dimensionExpression {
      return """
                Benchmark(
                  \(String(reflecting: benchmarkCase.name)),
                  dimension: \(dimension),
                  traits: \(renderTraits(benchmarkCase.traits)),
                  sourceLocation: \(benchmarkCase.sourceLocation.rendered),
                  input: { $0 }
                ) { __benchmarkScale in
        \(indent(benchmarkCase.invocation, spaces: 10))
                }
        """
    }
    return """
              Benchmark(
                \(String(reflecting: benchmarkCase.name)),
                traits: \(renderTraits(benchmarkCase.traits)),
                sourceLocation: \(benchmarkCase.sourceLocation.rendered)
              ) {
      \(indent(benchmarkCase.invocation, spaces: 10))
              }
      """
  }

  private func renderTraits(_ traits: [String]) -> String {
    "[\(traits.joined(separator: ", "))]"
  }

  private func indent(_ text: String, spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { "\(prefix)\($0)" }
      .joined(separator: "\n")
  }
}

/// Writes the host's `main.swift`, which hands every discovery type to
/// `BenchmarkHost`.
func writeGeneratedBenchmarkHost(
  workDirectory: URL,
  importedModules: [String],
  discoveryExpressions: [String]
) throws -> URL {
  let directory = workDirectory.appendingPathComponent("GeneratedBenchmarkHost")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let sourceURL = directory.appendingPathComponent("main.swift")
  let imports = Set(importedModules).sorted()
    .map { "import \($0)" }
    .joined(separator: "\n")
  let discoveryList =
    discoveryExpressions
    .map { "    \($0)" }
    .joined(separator: ",\n")
  let source = """
    import Benchmark
    import Report
    \(imports)

    @main
    struct GeneratedBenchmarkHost {
      static func main() async {
        await BenchmarkHost.run(discoveries: [
    \(discoveryList)
        ])
      }
    }
    """
  try source.write(to: sourceURL, atomically: true, encoding: .utf8)
  return sourceURL
}

/// `name` with every character that cannot appear in an identifier replaced
/// by `_`.
func sanitizedIdentifier(_ name: String) -> String {
  let scalars = name.unicodeScalars.map { scalar -> String in
    CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
  }
  let identifier = scalars.joined()
  return identifier.isEmpty ? "BenchmarkSuite" : identifier
}
