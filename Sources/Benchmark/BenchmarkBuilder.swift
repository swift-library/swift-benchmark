// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

@resultBuilder
public enum BenchmarkBuilder {
  public static func buildBlock(_ components: BenchmarkCase...) -> [BenchmarkCase] {
    components
  }

  public static func buildBlock(_ components: [BenchmarkCase]...) -> [BenchmarkCase] {
    components.flatMap { $0 }
  }

  public static func buildExpression(_ expression: BenchmarkCase) -> [BenchmarkCase] {
    [expression]
  }

  public static func buildExpression(_ expression: Benchmark) -> [BenchmarkCase] {
    [expression.benchmarkCase]
  }

  public static func buildExpression(_ expression: [BenchmarkCase]) -> [BenchmarkCase] {
    expression
  }

  public static func buildExpression(_ expression: [Benchmark]) -> [BenchmarkCase] {
    expression.map(\.benchmarkCase)
  }

  public static func buildOptional(_ component: [BenchmarkCase]?) -> [BenchmarkCase] {
    component ?? []
  }

  public static func buildEither(first component: [BenchmarkCase]) -> [BenchmarkCase] {
    component
  }

  public static func buildEither(second component: [BenchmarkCase]) -> [BenchmarkCase] {
    component
  }

  public static func buildArray(_ components: [[BenchmarkCase]]) -> [BenchmarkCase] {
    components.flatMap { $0 }
  }
}
