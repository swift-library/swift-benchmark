// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

/// Gives one step at a time exclusive use of the process for measurement.
///
/// The counting pass installs process-wide runtime hooks, and parallel
/// measurements disturb each other's times, so a runner holds the gate from
/// a step's warmup through its counting pass. A workload must not run a
/// benchmark runner itself, because it would wait for its own step.
actor MeasurementGate {
  static let shared = MeasurementGate()

  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  /// Runs `body` once no other step is measuring.
  nonisolated func withExclusiveAccess<T: Sendable>(
    _ body: () async throws -> T
  ) async throws -> T {
    await acquire()
    do {
      let result = try await body()
      await release()
      return result
    } catch {
      await release()
      throw error
    }
  }

  private func acquire() async {
    guard busy else {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  private func release() {
    guard !waiters.isEmpty else {
      busy = false
      return
    }
    waiters.removeFirst().resume()
  }
}
