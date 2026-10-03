// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Testing

@Suite("Benchmark Core Model")
struct BenchmarkCoreModelTests {
  @Test
  func suiteCanBeEmpty() {
    let suite = BenchmarkSuite("Empty")
    #expect(suite.name == "Empty")
    #expect(suite.cases.isEmpty)
  }

  @Test
  func suiteCanDeclareOneCaseWithBenchmarkAlias() {
    let suite = BenchmarkSuite("Parser") {
      Benchmark("Parse") {}
    }

    #expect(suite.cases.map(\.name) == ["Parse"])
  }

  @Test
  func benchmarkCapturesUserCallSiteSourceLocation() {
    let suite = BenchmarkSuite("Parser") {
      Benchmark("Parse") {}
    }
    let benchmarkCase = suite.cases[0]

    #expect(benchmarkCase.sourceLocation.fileID.contains("BenchmarkCoreModelTests"))
    #expect(benchmarkCase.sourceLocation.filePath.hasSuffix("BenchmarkCoreModelTests.swift"))
  }

  @Test
  func suiteCanDeclareMultipleCases() {
    let includeTokenize = true
    let suite = BenchmarkSuite("Parser") {
      Benchmark("Parse") {}
      if includeTokenize {
        Benchmark("Tokenize") {}
      }
      for index in 0..<2 {
        Benchmark("Generated\(index)") {}
      }
    }

    #expect(suite.cases.map(\.name) == ["Parse", "Tokenize", "Generated0", "Generated1"])
  }

  @Test
  func configurationDefaultsMatchPlan() throws {
    let counts = try BenchmarkConfiguration.default.validatedCounts()
    #expect(counts.warmup == 1)
    #expect(counts.iterations == 10)
  }
}
