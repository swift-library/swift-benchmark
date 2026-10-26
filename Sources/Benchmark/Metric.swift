// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension Benchmark {
  /// A quantity the runner measures for a benchmark case.
  ///
  /// Sample values are per single call of the workload, so a sample measured
  /// over a batch of calls reports the batch total divided by the batch size.
  /// ``peakMemory`` is the exception and is recorded once per step.
  ///
  /// A metric's identity is its ``name``: two metrics with the same name are
  /// equal whatever their unit, direction and ``isComparedByDefault``, and
  /// reports key values by name.
  /// The names of ``builtIn`` metrics are reserved for the runner.
  public struct Metric: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The unit a metric's values are expressed in.
    public enum Unit: String, Sendable, Hashable, Codable {
      /// Time in nanoseconds.
      case nanoseconds
      /// An amount of memory in bytes.
      case bytes
      /// A number of events or items.
      case count
    }

    /// Which direction of change counts as an improvement.
    public enum Direction: String, Sendable, Hashable, Codable {
      /// A decrease is an improvement, as for times, counts and bytes.
      case lowerIsBetter
      /// An increase is an improvement, as for throughput.
      case higherIsBetter
    }

    /// The metric's identity, used as its key in reports.
    public var name: String
    /// The unit of the metric's values.
    public var unit: Unit
    /// Whether a lower or a higher value is an improvement; decides which
    /// change a baseline comparison or budget treats as a regression.
    public var direction: Direction
    /// Whether baseline comparisons judge the metric without a threshold
    /// given for it. Metrics the environment moves more than the code, such as
    /// context switches, are reported but judged only on request.
    public var isComparedByDefault: Bool

    /// Creates a metric. Custom metrics need a name that no ``builtIn``
    /// metric uses.
    public init(
      name: String,
      unit: Unit,
      direction: Direction = .lowerIsBetter,
      isComparedByDefault: Bool = true
    ) {
      self.name = name
      self.unit = unit
      self.direction = direction
      self.isComparedByDefault = isComparedByDefault
    }

    /// The metric's name.
    public var description: String {
      name
    }

    /// Whether two metrics have the same name.
    public static func == (lhs: Metric, rhs: Metric) -> Bool {
      lhs.name == rhs.name
    }

    /// Hashes the metric's name.
    public func hash(into hasher: inout Hasher) {
      hasher.combine(name)
    }

    /// Elapsed wall-clock time per call.
    public static let wallClock = Metric(name: "wallClock", unit: .nanoseconds)

    /// User plus system CPU time of the whole process per call.
    public static let cpuTime = Metric(name: "cpuTime", unit: .nanoseconds)

    /// Instructions retired per call.
    ///
    /// Varies far less with machine load than time does. Apple platforms count
    /// the whole process. Linux counts user-mode instructions of the thread
    /// that runs the batch and the threads it creates, so it records the
    /// metric only for synchronous workloads, and only where the kernel lets
    /// the process open hardware counters.
    public static let instructions = Metric(name: "instructions", unit: .count)

    /// Processor cycles per call, counted like ``instructions``.
    public static let cycles = Metric(name: "cycles", unit: .count)

    /// Context switches of the process per call. Reported, but judged only
    /// when a threshold or budget names it.
    public static let contextSwitches = Metric(
      name: "contextSwitches", unit: .count, isComparedByDefault: false)

    /// Page faults of the process per call, minor and major. Reported, but
    /// judged only when a threshold or budget names it.
    public static let pageFaults = Metric(
      name: "pageFaults", unit: .count, isComparedByDefault: false)

    /// System calls of the process per call, on Apple platforms. Reported, but
    /// judged only when a threshold or budget names it.
    public static let systemCalls = Metric(
      name: "systemCalls", unit: .count, isComparedByDefault: false)

    /// Bytes the process read from storage per call, on macOS and Linux. Reads
    /// served from the page cache do not count. Reported, but judged only when
    /// a threshold or budget names it.
    public static let diskReadBytes = Metric(
      name: "diskReadBytes", unit: .bytes, isComparedByDefault: false)

    /// Bytes the process wrote to storage per call, on macOS and Linux.
    /// Reported, but judged only when a threshold or budget names it.
    public static let diskWriteBytes = Metric(
      name: "diskWriteBytes", unit: .bytes, isComparedByDefault: false)

    /// Swift heap objects the Swift runtime allocated per call, by any thread of
    /// the process.
    ///
    /// Counted in a separate pass after the timed samples, so counting does not
    /// slow the timed calls. Only allocations through the Swift runtime count:
    /// memory a C or C++ library allocates with `malloc`, and Objective-C
    /// objects, are in ``heapAllocations``. Apple platforms count in any
    /// process. Linux counts only in the counting host process, and only the
    /// calls compiled code makes into the runtime, not those the runtime makes
    /// to itself.
    public static let swiftAllocations = Metric(name: "swiftAllocations", unit: .count)

    /// Bytes requested by the allocations counted in ``swiftAllocations``.
    public static let swiftAllocatedBytes = Metric(name: "swiftAllocatedBytes", unit: .bytes)

    /// Swift strong retains per call, counted with ``swiftAllocations``.
    public static let swiftRetains = Metric(name: "swiftRetains", unit: .count)

    /// Swift strong releases per call, counted with ``swiftAllocations``.
    public static let swiftReleases = Metric(name: "swiftReleases", unit: .count)

    /// System allocator calls per call that returned memory, by any thread of
    /// the process: `malloc` and its relatives, through which C, C++,
    /// Objective-C and the Swift runtime allocate.
    ///
    /// Counted only in the counting host process that the package workflow
    /// starts for each step with the interposer library loaded; other
    /// processes leave it out.
    public static let heapAllocations = Metric(name: "heapAllocations", unit: .count)

    /// Bytes requested by the allocations counted in ``heapAllocations``. A
    /// reallocation counts its new size.
    public static let heapAllocatedBytes = Metric(name: "heapAllocatedBytes", unit: .bytes)

    /// Allocations per call left unfreed when the batch ends:
    /// ``heapAllocations`` minus frees. A steady positive value means each call
    /// keeps memory, as a leak or a growing cache does.
    public static let heapNetAllocations = Metric(name: "heapNetAllocations", unit: .count)

    /// How far the process's physical memory footprint rose above its level at
    /// the start of the step, recorded once per step.
    ///
    /// Platforms report only the highest footprint over the process lifetime,
    /// so the runner records this metric only when told it owns the process,
    /// and leaves it out when the footprint never exceeded the peak it had
    /// already reached before the step.
    public static let peakMemory = Metric(name: "peakMemory", unit: .bytes)

    /// The metrics the runner measures without user code.
    public static let builtIn: [Metric] = [
      .wallClock, .cpuTime, .instructions, .cycles, .contextSwitches, .pageFaults,
      .systemCalls, .diskReadBytes, .diskWriteBytes, .swiftAllocations, .swiftAllocatedBytes,
      .swiftRetains, .swiftReleases, .heapAllocations, .heapAllocatedBytes, .heapNetAllocations,
      .peakMemory,
    ]
  }
}
