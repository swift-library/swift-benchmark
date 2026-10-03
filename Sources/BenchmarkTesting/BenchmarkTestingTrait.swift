// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Report

#if canImport(Testing)
  import Testing

  public struct BenchmarkTestingTrait: TestTrait, SuiteTrait {
    public var configuration: BenchmarkConfiguration?
    public var baseline: BaselineDocument?
    public var baselineMetric: Report.Measurement.Metric
    public var threshold: ThresholdPolicy
    public var budgets: [BudgetPolicy]

    public init(
      configuration: BenchmarkConfiguration? = nil,
      baseline: BaselineDocument? = nil,
      baselineMetric: Report.Measurement.Metric = .mean,
      threshold: ThresholdPolicy = .relativePercentage(10),
      budgets: [BudgetPolicy] = []
    ) {
      self.configuration = configuration
      self.baseline = baseline
      self.baselineMetric = baselineMetric
      self.threshold = threshold
      self.budgets = budgets
    }
  }

  extension TestTrait where Self == BenchmarkTestingTrait {
    public static func benchmark(
      configuration: BenchmarkConfiguration? = nil,
      baseline: BaselineDocument? = nil,
      baselineMetric: Report.Measurement.Metric = .mean,
      threshold: ThresholdPolicy = .relativePercentage(10),
      budgets: [BudgetPolicy] = []
    ) -> BenchmarkTestingTrait {
      BenchmarkTestingTrait(
        configuration: configuration,
        baseline: baseline,
        baselineMetric: baselineMetric,
        threshold: threshold,
        budgets: budgets
      )
    }
  }

  extension SuiteTrait where Self == BenchmarkTestingTrait {
    public static func benchmark(
      configuration: BenchmarkConfiguration? = nil,
      baseline: BaselineDocument? = nil,
      baselineMetric: Report.Measurement.Metric = .mean,
      threshold: ThresholdPolicy = .relativePercentage(10),
      budgets: [BudgetPolicy] = []
    ) -> BenchmarkTestingTrait {
      BenchmarkTestingTrait(
        configuration: configuration,
        baseline: baseline,
        baselineMetric: baselineMetric,
        threshold: threshold,
        budgets: budgets
      )
    }
  }
#endif
