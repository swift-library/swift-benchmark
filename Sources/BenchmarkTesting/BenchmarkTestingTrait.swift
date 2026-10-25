// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Report

#if canImport(Testing)
  import Testing

  public struct BenchmarkTestingTrait: TestTrait, SuiteTrait {
    public var configuration: BenchmarkConfiguration?
    public var baseline: BaselineDocument?
    public var comparison: ComparisonPolicy

    public init(
      configuration: BenchmarkConfiguration? = nil,
      baseline: BaselineDocument? = nil,
      comparison: ComparisonPolicy = .default
    ) {
      self.configuration = configuration
      self.baseline = baseline
      self.comparison = comparison
    }
  }

  extension TestTrait where Self == BenchmarkTestingTrait {
    public static func benchmark(
      configuration: BenchmarkConfiguration? = nil,
      baseline: BaselineDocument? = nil,
      comparison: ComparisonPolicy = .default
    ) -> BenchmarkTestingTrait {
      BenchmarkTestingTrait(
        configuration: configuration, baseline: baseline, comparison: comparison)
    }
  }

  extension SuiteTrait where Self == BenchmarkTestingTrait {
    public static func benchmark(
      configuration: BenchmarkConfiguration? = nil,
      baseline: BaselineDocument? = nil,
      comparison: ComparisonPolicy = .default
    ) -> BenchmarkTestingTrait {
      BenchmarkTestingTrait(
        configuration: configuration, baseline: baseline, comparison: comparison)
    }
  }
#endif
