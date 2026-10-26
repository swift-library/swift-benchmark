// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

#ifndef BENCHMARK_INTERPOSER_H
#define BENCHMARK_INTERPOSER_H

#include <stdint.h>

/// The counts the interposer keeps. A counting host process loads the
/// interposer before any other library, and the benchmark runner reaches these
/// functions through `dlsym`, so the names and values are the runner's
/// contract with the library.
typedef enum {
  /// System allocator calls that returned memory, on every thread.
  benchmark_interposer_heap_allocations = 0,
  /// Bytes those calls requested.
  benchmark_interposer_heap_allocated_bytes = 1,
  /// System allocator calls that freed memory.
  benchmark_interposer_heap_frees = 2,
  /// `swift_allocObject` calls. Linux only.
  benchmark_interposer_swift_allocations = 3,
  /// Bytes `swift_allocObject` calls requested. Linux only.
  benchmark_interposer_swift_allocated_bytes = 4,
  /// Strong retains, counting `swift_retain_n` by its count. Linux only.
  benchmark_interposer_swift_retains = 5,
  /// Strong releases, counting `swift_release_n` by its count. Linux only.
  benchmark_interposer_swift_releases = 6,
} benchmark_interposer_counter;

/// Resets every count to zero and starts counting.
void benchmark_interposer_start(void);

/// Stops counting. The counts keep their values until the next start.
void benchmark_interposer_stop(void);

/// The value of `counter` since the last start, or `UINT64_MAX` where this
/// platform's interposer does not count it.
uint64_t benchmark_interposer_count(benchmark_interposer_counter counter);

#endif
