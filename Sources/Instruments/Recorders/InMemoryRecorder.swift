// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Dispatch
import Foundation

public final class InMemoryRecorder: Recorder, @unchecked Sendable {
  private let lock = NSLock()
  private var state = State()
  private let clock: @Sendable () -> UInt64
  private let stackKey: @Sendable () -> UInt64

  public init(
    clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    stackKey: @escaping @Sendable () -> UInt64 = { UInt64(bitPattern: Int64(Thread.current.hash)) }
  ) {
    self.clock = clock
    self.stackKey = stackKey
  }

  public func beginSpan(_ name: StaticString, attributes: SpanAttributes) -> SpanToken {
    lock.withLock {
      let key = stackKey()
      let spanID = state.nextSpanID()
      let parentID = state.stacks[key]?.last
      let record = Timeline.SpanRecord(
        id: spanID,
        parentID: parentID,
        name: String(describing: name),
        start: clock(),
        end: nil,
        attributes: attributes
      )
      state.spanIndexes[spanID] = state.timeline.spans.count
      state.timeline.spans.append(record)
      state.stacks[key, default: []].append(spanID)
      return SpanToken(storage: InMemorySpanTokenStorage(id: spanID, stackKey: key))
    }
  }

  public func endSpan(_ token: SpanToken) {
    guard let storage = token.storage as? InMemorySpanTokenStorage else {
      return
    }

    lock.withLock {
      if let index = state.spanIndexes[storage.id],
        state.timeline.spans[index].end == nil
      {
        state.timeline.spans[index].end = clock()
      }

      guard var stack = state.stacks[storage.stackKey] else {
        return
      }

      if stack.last == storage.id {
        _ = stack.popLast()
      } else if let index = stack.lastIndex(of: storage.id) {
        stack.remove(at: index)
      }

      if stack.isEmpty {
        state.stacks.removeValue(forKey: storage.stackKey)
      } else {
        state.stacks[storage.stackKey] = stack
      }
    }
  }

  public func recordEvent(_ name: StaticString, attributes: SpanAttributes) {
    lock.withLock {
      let key = stackKey()
      let eventID = state.nextEventID()
      state.timeline.events.append(
        Timeline.EventRecord(
          id: eventID,
          parentSpanID: state.stacks[key]?.last,
          name: String(describing: name),
          timestamp: clock(),
          attributes: attributes
        )
      )
    }
  }

  public func snapshot() -> Timeline {
    lock.withLock {
      state.timeline
    }
  }

  public func reset() {
    lock.withLock {
      state = State()
    }
  }

  private struct State {
    var timeline = Timeline()
    var spanIndexes: [Timeline.SpanID: Int] = [:]
    var stacks: [UInt64: [Timeline.SpanID]] = [:]
    var nextSpanRawID: UInt64 = 1
    var nextEventRawID: UInt64 = 1

    mutating func nextSpanID() -> Timeline.SpanID {
      defer {
        nextSpanRawID += 1
      }
      return Timeline.SpanID(rawValue: nextSpanRawID)
    }

    mutating func nextEventID() -> Timeline.EventID {
      defer {
        nextEventRawID += 1
      }
      return Timeline.EventID(rawValue: nextEventRawID)
    }
  }
}

private struct InMemorySpanTokenStorage: SpanTokenStorage {
  let id: Timeline.SpanID
  let stackKey: UInt64
}
