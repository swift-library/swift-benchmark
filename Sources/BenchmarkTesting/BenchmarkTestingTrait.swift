// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark

#if canImport(Testing)
  import Testing

  /// Enrolls a Swift Testing suite or test in the package benchmark workflow.
  ///
  /// `swift package benchmark` measures enrolled tests with `configuration`,
  /// or the suite's or the default configuration; `swift test` still runs
  /// each test once. The workflow reads the trait from source, so its
  /// argument must be an expression the generated bridge can evaluate.
  public struct BenchmarkTestingTrait: TestTrait, SuiteTrait {
    /// The configuration enrolled tests are measured with.
    public var configuration: BenchmarkConfiguration?

    /// Creates a trait.
    public init(configuration: BenchmarkConfiguration? = nil) {
      self.configuration = configuration
    }
  }

  extension TestTrait where Self == BenchmarkTestingTrait {
    /// Enrolls this test in the package benchmark workflow.
    public static func benchmark(configuration: BenchmarkConfiguration? = nil)
      -> BenchmarkTestingTrait
    {
      BenchmarkTestingTrait(configuration: configuration)
    }
  }

  extension SuiteTrait where Self == BenchmarkTestingTrait {
    /// Enrolls every test in this suite in the package benchmark workflow.
    public static func benchmark(configuration: BenchmarkConfiguration? = nil)
      -> BenchmarkTestingTrait
    {
      BenchmarkTestingTrait(configuration: configuration)
    }
  }
#endif
