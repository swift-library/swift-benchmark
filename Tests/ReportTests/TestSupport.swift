// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Instruments
import Report

extension RunMetadata {
  static func fixture() -> RunMetadata {
    RunMetadata(
      id: "run:test",
      swiftVersion: "6.3.1",
      packageIdentity: "swift-benchmark",
      gitCommit: "fixture",
      platform: "macOS",
      architecture: "arm64",
      osVersion: "15",
      generatedAt: "2026-05-11T00:00:00Z",
      buildConfiguration: "debug"
    )
  }
}

/// A clock whose readings advance by `step` nanoseconds each time it is read.
struct StepClock: BenchmarkClock {
  let step: UInt64
  private let state = StepClockState()

  init(step: UInt64) {
    self.step = step
  }

  func now() -> BenchmarkInstant {
    state.advance(by: step)
  }
}

private final class StepClockState: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 0

  func advance(by step: UInt64) -> BenchmarkInstant {
    lock.withLock {
      value += step
      return BenchmarkInstant(nanoseconds: value)
    }
  }
}

/// Hands out preset timestamps, one per reading.
final class TickClock: @unchecked Sendable {
  private var ticks: [UInt64]

  init(_ ticks: [UInt64]) {
    self.ticks = ticks
  }

  func next() -> UInt64 {
    ticks.removeFirst()
  }
}

func wallClockSamples(_ values: [Double]) -> [Sample] {
  values.enumerated().map { Sample(iteration: $0.offset, values: [.wallClock: $0.element]) }
}

func baselineCase(_ suiteName: String, _ caseName: String, wallClock: [Double])
  -> BaselineCase
{
  BaselineCase(
    suiteName: suiteName,
    caseName: caseName,
    measurement: Report.Measurement(
      samples: wallClock.enumerated().map { index, value in
        SampleReport(
          id: ReportID(rawValue: "sample:baseline.\(index)"),
          iterationID: ReportID(rawValue: "iteration:baseline.\(index)"),
          iteration: index,
          values: ["wallClock": value]
        )
      },
      metrics: [.wallClock]
    )
  )
}

func makeTimeline() -> Timeline {
  let clock = TickClock([10, 30, 31])
  let recorder = InMemoryRecorder(
    clock: {
      clock.next()
    },
    stackKey: { 1 }
  )
  let attributes: SpanAttributes = [
    TimelineCorrelationKeys.suite: "Parser",
    TimelineCorrelationKeys.case: "ParseDocument",
    TimelineCorrelationKeys.iteration: 1,
  ]
  let token = recorder.beginSpan("ParseAST", attributes: attributes)
  recorder.endSpan(token)
  recorder.recordEvent("CacheMiss", attributes: attributes)
  return recorder.snapshot()
}

func makeNestedTimeline() -> Timeline {
  let clock = TickClock([10, 11, 12, 19, 20])
  let recorder = InMemoryRecorder(
    clock: {
      clock.next()
    },
    stackKey: { 1 }
  )
  let attributes: SpanAttributes = [
    TimelineCorrelationKeys.suite: "Parser",
    TimelineCorrelationKeys.case: "ParseDocument",
    TimelineCorrelationKeys.iteration: 1,
  ]
  let parent = recorder.beginSpan("IterationRoot", attributes: attributes)
  let child = recorder.beginSpan("ParseAST", attributes: .empty)
  recorder.recordEvent("CacheMiss", attributes: .empty)
  recorder.endSpan(child)
  recorder.endSpan(parent)
  return recorder.snapshot()
}

func reportFixtureURL(_ name: String) -> URL {
  Bundle.module.url(forResource: name, withExtension: nil)!
}
