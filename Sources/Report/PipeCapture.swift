// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Dispatch
import Foundation

/// Drains a pipe on a background queue, so a chatty child cannot block on a
/// full pipe while the parent waits for it to exit.
package final class PipeCapture: @unchecked Sendable {
  private let group = DispatchGroup()
  private let lock = NSLock()
  private var data = Data()

  package init() {}

  package func startReading(_ fileHandle: FileHandle) {
    group.enter()
    DispatchQueue.global(qos: .utility).async { [self] in
      let captured = fileHandle.readDataToEndOfFile()
      lock.withLock { data.append(captured) }
      group.leave()
    }
  }

  /// Everything the pipe carried, once its writers have closed it.
  package func string() -> String {
    group.wait()
    return String(decoding: lock.withLock { data }, as: UTF8.self)
  }
}
