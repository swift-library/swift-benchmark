// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension Benchmark {
  /// A quantity the runner measures for a benchmark case.
  ///
  /// Sample values are per single call of the workload, so a sample measured
  /// over a batch of calls reports the batch total divided by the batch size.
  /// Metrics are identified by ``name``; reports key values by that name.
  public struct Metric: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The unit a metric's values are expressed in.
    public enum Unit: String, Sendable, Hashable, Codable {
      case nanoseconds
      case bytes
      case count
    }

    /// Which direction of change counts as an improvement.
    public enum Direction: String, Sendable, Hashable, Codable {
      case lowerIsBetter
      case higherIsBetter
    }

    public var name: String
    public var unit: Unit
    public var direction: Direction

    public init(name: String, unit: Unit, direction: Direction = .lowerIsBetter) {
      self.name = name
      self.unit = unit
      self.direction = direction
    }

    public var description: String {
      name
    }

    /// Elapsed wall-clock time per call.
    public static let wallClock = Metric(name: "wallClock", unit: .nanoseconds)

    /// The metrics the runner can measure without user code.
    public static let builtIn: [Metric] = [.wallClock]
  }
}
