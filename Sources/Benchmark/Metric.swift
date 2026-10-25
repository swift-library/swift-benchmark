// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension Benchmark {
  /// A quantity the runner measures for a benchmark case.
  ///
  /// Sample values are per single call of the workload, so a sample measured
  /// over a batch of calls reports the batch total divided by the batch size.
  /// ``peakMemory`` is the exception and is recorded once per step. Metrics are
  /// identified by ``name``; reports key values by that name.
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

    /// User plus system CPU time of the whole process per call.
    public static let cpuTime = Metric(name: "cpuTime", unit: .nanoseconds)

    /// Swift heap objects allocated per call, by any thread of the process.
    ///
    /// Counted in a separate pass after the timed samples, so counting does not
    /// slow the timed calls. Allocations made directly through `malloc` or by
    /// Objective-C are not counted.
    public static let allocations = Metric(name: "allocations", unit: .count)

    /// Bytes requested by the Swift heap allocations counted in ``allocations``.
    public static let allocatedBytes = Metric(name: "allocatedBytes", unit: .bytes)

    /// Swift strong retains per call, counted with ``allocations``.
    public static let retains = Metric(name: "retains", unit: .count)

    /// Swift strong releases per call, counted with ``allocations``.
    public static let releases = Metric(name: "releases", unit: .count)

    /// The highest physical memory footprint the process reached, recorded once
    /// per step. It is recorded only when the process measures a single step,
    /// because an earlier step's peak would otherwise be reported again.
    public static let peakMemory = Metric(name: "peakMemory", unit: .bytes)

    /// The metrics the runner measures without user code.
    public static let builtIn: [Metric] = [
      .wallClock, .cpuTime, .allocations, .allocatedBytes, .retains, .releases, .peakMemory,
    ]
  }
}
