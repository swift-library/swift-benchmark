// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

extension Benchmark {
  public struct ArgumentValue: Sendable, Equatable, Hashable, Codable {
    public var label: String
    public var parameterName: String?
    public var scale: Benchmark.Scale?

    public init(
      label: String,
      parameterName: String? = nil,
      scale: Benchmark.Scale? = nil
    ) {
      self.label = label
      self.parameterName = parameterName
      self.scale = scale
    }

    public init<Value>(
      _ value: Value,
      parameterName: String? = nil
    ) {
      self.init(
        label: String(describing: value),
        parameterName: parameterName,
        scale: Benchmark.Scale(inferring: value)
      )
    }
  }

  public struct ArgumentRow: Sendable, Equatable, Hashable, Codable {
    public var id: String?
    public var arguments: [Benchmark.ArgumentValue]
    public var scale: Benchmark.Scale?

    public init(
      id: String? = nil,
      arguments: [Benchmark.ArgumentValue] = [],
      scale: Benchmark.Scale? = nil
    ) {
      self.id = id
      self.arguments = arguments
      self.scale = scale ?? Self.inferredScale(from: arguments)
    }

    public static var unparameterized: Benchmark.ArgumentRow {
      Benchmark.ArgumentRow()
    }

    private static func inferredScale(
      from arguments: [Benchmark.ArgumentValue]
    ) -> Benchmark.Scale? {
      let scales = arguments.compactMap(\.scale)
      guard scales.count == 1 else {
        return nil
      }
      return scales[0]
    }
  }
}

extension Benchmark.Scale {
  public init?<Value>(inferring value: Value) {
    if let integer = value as? any BinaryInteger,
      let exact = Int(exactly: integer)
    {
      self.init(exact)
      return
    }

    if let rawRepresentable = value as? any RawRepresentable,
      let integer = rawRepresentable.rawValue as? any BinaryInteger,
      let exact = Int(exactly: integer)
    {
      self.init(exact)
      return
    }

    return nil
  }
}

struct BenchmarkCaseRow: Sendable {
  var metadata: Benchmark.ArgumentRow
  var makeOperation: @Sendable () async throws -> @Sendable () async throws -> Void
}
