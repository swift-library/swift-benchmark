// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Instruments

public final class BenchmarkTimelineObserver: BenchmarkExecutionObserver, @unchecked Sendable {
  public let recorder: InMemoryRecorder

  private let lock = NSLock()
  private var captures: [String: IterationCapture] = [:]

  public init(recorder: InMemoryRecorder = InMemoryRecorder()) {
    self.recorder = recorder
  }

  public func benchmarkWillRun(context: BenchmarkExecutionContext) async {
    guard case .measurement(let iteration) = context.phase else {
      return
    }
    let previousRecorder = Instruments.current
    let compositeRecorder = CompositeRecorder([recorder, previousRecorder])
    let scope = Instruments.beginCurrentRecorderScope(compositeRecorder)
    let token = compositeRecorder.beginSpan(
      "BenchmarkIteration",
      attributes: correlationAttributes(context: context, iteration: iteration)
    )
    lock.withLock {
      captures[key(context)] = IterationCapture(
        recorder: compositeRecorder,
        token: token,
        scope: scope
      )
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
      attributes.values[TimelineCorrelationKeys.durationNanoseconds] = .int(
        Int(durationNanoseconds))
    }
    endSpan(for: context, eventName: "BenchmarkIterationMeasured", eventAttributes: attributes)
  }

  public func benchmarkDidFail(context: BenchmarkExecutionContext, error: any Error) async {
    endSpan(for: context)
  }

  private func endSpan(
    for context: BenchmarkExecutionContext,
    eventName: StaticString? = nil,
    eventAttributes: SpanAttributes = .empty
  ) {
    let capture = lock.withLock {
      captures.removeValue(forKey: key(context))
    }
    if let capture {
      if let eventName {
        capture.recorder.recordEvent(eventName, attributes: eventAttributes)
      }
      capture.recorder.endSpan(capture.token)
      capture.scope.restore()
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
      TimelineCorrelationKeys.dimensionSize: context.size.map { .int($0.rawValue) }
        ?? .string("none"),
    ]
  }
}

private struct IterationCapture: Sendable {
  var recorder: any Recorder
  var token: SpanToken
  var scope: Instruments.RecorderScope
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
