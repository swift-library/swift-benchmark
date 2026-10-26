// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

// What the Benchmark runner reads from the platform through C: hardware
// counters, and the symbols of return addresses.

#ifndef BENCHMARK_PLATFORM_H
#define BENCHMARK_PLATFORM_H

#include <stdint.h>

/// The hardware events `benchmark_thread_counter_open` can count.
typedef enum {
  benchmark_thread_counter_instructions = 0,
  benchmark_thread_counter_cycles = 1,
} benchmark_thread_counter_kind;

/// Starts counting `kind` in user mode for the calling thread and the threads
/// it creates, and returns a handle for `benchmark_thread_counter_read`.
/// Returns -1 where the platform or its permissions provide no such counter.
/// Only Linux provides one; it counts through `perf_event_open`.
int benchmark_thread_counter_open(benchmark_thread_counter_kind kind);

/// Stores the events counted since the counter opened in `value`. Returns 0
/// on success and -1 otherwise.
int benchmark_thread_counter_read(int counter, uint64_t *value);

/// Stops the counter and releases its handle.
void benchmark_thread_counter_close(int counter);

/// Looks up the loaded image and the nearest symbol containing `address`, as
/// `dladdr` does. Returns 0 when no loaded image contains it; `symbol` is
/// `NULL` when the image has no symbol for it.
int benchmark_symbol_at(
  const void *address, const char **symbol, const char **image, uintptr_t *image_base);

#endif
