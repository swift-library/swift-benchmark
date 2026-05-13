import Benchmark
import Foundation
import Instruments

public final class BenchmarkTimelineObserver: BenchmarkExecutionObserver, @unchecked Sendable {
  public let recorder: InMemoryRecorder

  private let lock = NSLock()
  private var tokens: [String: SpanToken] = [:]

  public init(recorder: InMemoryRecorder = InMemoryRecorder()) {
    self.recorder = recorder
  }

  public func benchmarkWillRun(context: BenchmarkExecutionContext) async {
    guard case .measurement(let iteration) = context.phase else {
      return
    }
    let token = recorder.beginSpan(
      "BenchmarkIteration",
      attributes: correlationAttributes(context: context, iteration: iteration)
    )
    lock.withLock {
      tokens[key(context)] = token
    }
  }

  public func benchmarkDidRun(
    context: BenchmarkExecutionContext,
    durationNanoseconds: UInt64?
  ) async {
    guard case .measurement(let iteration) = context.phase else {
      return
    }
    var attributes = correlationAttributes(context: context, iteration: iteration)
    if let durationNanoseconds {
      attributes.values[TimelineCorrelationKeys.durationNanoseconds] = .int(Int(durationNanoseconds))
    }
    recorder.recordEvent("BenchmarkIterationMeasured", attributes: attributes)
    endSpan(for: context)
  }

  public func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async {
    endSpan(for: context)
  }

  private func endSpan(for context: BenchmarkExecutionContext) {
    let token = lock.withLock {
      tokens.removeValue(forKey: key(context))
    }
    if let token {
      recorder.endSpan(token)
    }
  }

  private func key(_ context: BenchmarkExecutionContext) -> String {
    "\(context.suiteName)\u{0}\(context.caseName)\u{0}\(context.phase)"
  }

  private func correlationAttributes(
    context: BenchmarkExecutionContext,
    iteration: Int
  ) -> SpanAttributes {
    [
      TimelineCorrelationKeys.suite: .string(context.suiteName),
      TimelineCorrelationKeys.case: .string(context.caseName),
      TimelineCorrelationKeys.iteration: .int(iteration),
      TimelineCorrelationKeys.dimensionSize: context.size.map { .int($0.rawValue) } ?? .string("none"),
    ]
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ operation: () throws -> T) rethrows -> T {
    lock()
    defer {
      unlock()
    }
    return try operation()
  }
}
