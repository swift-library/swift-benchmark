// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import Testing

@testable import _BenchmarkDiscoveryCore

@Suite("Discovery Planner")
struct DiscoveryPlannerTests {
  @Test
  func nativeSuitesBuildADeterministicPlanAndHostSource() throws {
    let fixture = try DiscoveryFixture()
    let library = try fixture.target(
      "FixtureLibrary", kind: "library",
      files: [
        "LibraryBenchmarks.swift": """
        import Benchmark

        @BenchmarkSuite("Parser")
        struct ParserBenchmarks {
          @Benchmark("Noop")
          func noop() {}
        }
        """
      ])

    let plan = try fixture.plan(library)

    #expect(
      plan.nativeDiscoveries.map(\.discoveryTypeName) == ["__BenchmarkDiscovery_ParserBenchmarks"])
    #expect(
      plan.discoveryExpressions == ["FixtureLibrary.__BenchmarkDiscovery_ParserBenchmarks.self"])
    #expect(plan.discoveredTargetNames == ["FixtureLibrary"])
    #expect(plan.requiresSwiftTesting == false)
    let hostSource = try String(contentsOfFile: plan.generatedHostSourcePath, encoding: .utf8)
    #expect(hostSource.contains("import FixtureLibrary"))
    #expect(hostSource.contains("FixtureLibrary.__BenchmarkDiscovery_ParserBenchmarks.self"))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try encoder.encode(plan) == encoder.encode(fixture.plan(library)))
  }

  @Test
  func librarySuitesMayDeclarePrivateBenchmarks() throws {
    let fixture = try DiscoveryFixture()
    let library = try fixture.target(
      "FixtureLibrary", kind: "library",
      files: [
        "LibraryBenchmarks.swift": """
        import Benchmark

        @BenchmarkSuite("Parser")
        struct ParserBenchmarks {
          @Benchmark("Noop")
          private func noop() {}
        }
        """
      ])

    #expect(try fixture.plan(library).nativeDiscoveries.map(\.typeName) == ["ParserBenchmarks"])
  }

  @Test
  func commentsAndStringLiteralsDeclareNothing() throws {
    let fixture = try DiscoveryFixture()
    let library = try fixture.target(
      "FixtureLibrary", kind: "library",
      files: [
        "LibraryBenchmarks.swift": #"""
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
      ])

    #expect(try fixture.plan(library).nativeDiscoveries.map(\.typeName) == ["RealBenchmarks"])
  }

  @Test
  func nestedSuitesAreReachedThroughTheirEnclosingType() throws {
    let fixture = try DiscoveryFixture()
    let library = try fixture.target(
      "FixtureLibrary", kind: "library",
      files: [
        "NestedBenchmarks.swift": """
        import Benchmark

        enum Outer {
          @BenchmarkSuite("Nested")
          struct InnerBenchmarks {
            @Benchmark("Noop")
            func noop() {}
          }
        }

        extension Outer {
          @BenchmarkSuite("Extended")
          struct ExtendedBenchmarks {
            @Benchmark("Noop")
            func noop() {}
          }
        }
        """
      ])

    let plan = try fixture.plan(library)

    #expect(
      plan.nativeDiscoveries.map(\.typeName) == [
        "Outer.InnerBenchmarks", "Outer.ExtendedBenchmarks",
      ])
    #expect(
      plan.discoveryExpressions == [
        "FixtureLibrary.Outer.__BenchmarkDiscovery_InnerBenchmarks.self",
        "FixtureLibrary.Outer.__BenchmarkDiscovery_ExtendedBenchmarks.self",
      ])
  }

  @Test
  func declarationsOnlyInAnExecutableTargetAskForAHost() throws {
    let fixture = try DiscoveryFixture()
    let tool = try fixture.target(
      "Tool", kind: "executable",
      files: [
        "Benchmarks.swift": """
        @BenchmarkSuite("Tool")
        struct ToolBenchmarks {
          @Benchmark("Noop")
          func noop() {}
        }
        """
      ])

    #expect {
      try fixture.plan(tool)
    } throws: { error in
      String(describing: error).contains("found only in executable target(s) Tool")
    }
  }
}
