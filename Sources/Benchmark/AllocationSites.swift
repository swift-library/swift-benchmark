// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

internal import _BenchmarkPlatform

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

extension Benchmark {
  /// Where the heap allocations of a row's counted batch came from: their
  /// call stacks, most allocations first.
  ///
  /// A counting host process records them when asked to, through the
  /// interposer library; other processes record none.
  public struct AllocationSites: Sendable, Equatable, Codable {
    /// The calls of the counted batch that the stacks' totals cover.
    public var calls: Int
    /// The stacks with the most allocations, at most ``stackLimit``.
    public var stacks: [AllocationStack]

    /// The most stacks a row keeps.
    public static let stackLimit = 50

    /// Creates sites for a batch of `calls` calls.
    public init(calls: Int, stacks: [AllocationStack]) {
      self.calls = calls
      self.stacks = stacks
    }
  }

  /// One call stack that allocated, with what it allocated over the counted
  /// batch.
  public struct AllocationStack: Sendable, Equatable, Codable {
    /// The functions on the stack, innermost first: the function that called
    /// the allocator, then its callers up to the benchmark's body. A frame
    /// without a symbol names its image and offset.
    public var frames: [String]
    /// Allocations made from this stack.
    public var allocations: Int
    /// Bytes those allocations requested.
    public var bytes: Int

    /// Creates a stack.
    public init(frames: [String], allocations: Int, bytes: Int) {
      self.frames = frames
      self.allocations = allocations
      self.bytes = bytes
    }
  }
}

extension Benchmark.AllocationSites {
  /// Symbolicates the stacks the interposer recorded for a batch of `calls`
  /// calls. Frames below the benchmark's body, which belong to the runner,
  /// are left out, and stacks that become equal are merged.
  init(calls: Int, recorded: [InterposerCounters.RecordedStack]) {
    var symbols: [UInt: String] = [:]
    func symbol(_ address: UInt) -> String {
      if let name = symbols[address] {
        return name
      }
      let name = Self.symbolicate(address)
      symbols[address] = name
      return name
    }

    var merged: [[String]: (allocations: Int, bytes: Int)] = [:]
    for stack in recorded {
      var frames: [String] = []
      for address in stack.frames {
        let frame = symbol(address)
        if Self.isRunnerFrame(frame) {
          break
        }
        frames.append(frame)
      }
      merged[frames, default: (0, 0)].allocations += stack.allocations
      merged[frames, default: (0, 0)].bytes += stack.bytes
    }
    let stacks = merged.map { frames, totals in
      Benchmark.AllocationStack(
        frames: frames, allocations: totals.allocations, bytes: totals.bytes)
    }
    .sorted { lhs, rhs in
      lhs.allocations != rhs.allocations
        ? lhs.allocations > rhs.allocations : lhs.frames.lexicographicallyPrecedes(rhs.frames)
    }
    self.init(calls: calls, stacks: Array(stacks.prefix(Self.stackLimit)))
  }

  /// Whether `frame` is the runner calling the benchmark's body; it and every
  /// frame below it are the runner's, not the benchmark's.
  private static func isRunnerFrame(_ frame: String) -> Bool {
    frame.contains("Benchmark.BenchmarkWorkload") || frame.contains("Benchmark.PreparedBatch")
  }

  /// The function containing `address`, demangled, or its image and offset
  /// without a symbol. Return addresses point after the call, so the address
  /// looked up is one byte earlier.
  private static func symbolicate(_ address: UInt) -> String {
    var symbol: UnsafePointer<CChar>?
    var image: UnsafePointer<CChar>?
    var imageBase: UInt = 0
    guard address > 0,
      benchmark_symbol_at(
        UnsafeRawPointer(bitPattern: address - 1), &symbol, &image, &imageBase) != 0
    else {
      return "0x\(String(address, radix: 16))"
    }
    if let symbol {
      return demangle(String(cString: symbol))
    }
    let imageName = image.map { String(cString: $0) }?.split(separator: "/").last
    let offset = address - imageBase
    return "\(imageName.map(String.init) ?? "?")+0x\(String(offset, radix: 16))"
  }

  /// `name` demangled as a Swift or C++ symbol, or unchanged.
  private static func demangle(_ name: String) -> String {
    let symbol = name.hasPrefix("_$s") || name.hasPrefix("__Z") ? String(name.dropFirst()) : name
    let demangled: UnsafeMutablePointer<CChar>?
    if symbol.hasPrefix("$s") {
      demangled = symbol.withCString { swiftDemangle($0, strlen($0), nil, nil, 0) }
    } else if symbol.hasPrefix("_Z"), let cxxDemangle = CxxDemangler.function {
      var status: Int32 = 0
      demangled = symbol.withCString { cxxDemangle($0, nil, nil, &status) }
    } else {
      demangled = nil
    }
    guard let demangled else {
      return name
    }
    defer { free(demangled) }
    return String(cString: demangled)
  }
}

/// The C++ ABI's demangler, found where the process loaded the C++ runtime:
/// it returns a `malloc`ed string, or `nil` for a name it cannot demangle.
private enum CxxDemangler {
  typealias Function =
    @convention(c) (
      UnsafePointer<CChar>, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?,
      UnsafeMutablePointer<Int32>
    ) -> UnsafeMutablePointer<CChar>?

  static let function = dynamicSymbol("__cxa_demangle").map {
    unsafeBitCast($0, to: Function.self)
  }
}

/// The Swift runtime's demangler: it returns a `malloc`ed string, or `nil`
/// for a name that is not a Swift symbol.
@_silgen_name("swift_demangle")
private func swiftDemangle(
  _ mangledName: UnsafePointer<CChar>,
  _ mangledNameLength: Int,
  _ outputBuffer: UnsafeMutablePointer<CChar>?,
  _ outputBufferSize: UnsafeMutablePointer<Int>?,
  _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
