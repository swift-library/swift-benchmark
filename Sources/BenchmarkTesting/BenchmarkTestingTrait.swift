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

  public extension TestTrait where Self == BenchmarkTestingTrait {
    static func benchmark(
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

  public extension SuiteTrait where Self == BenchmarkTestingTrait {
    static func benchmark(
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
