// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

#ifndef BENCHMARK_COUNTERS_H
#define BENCHMARK_COUNTERS_H

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

#endif
