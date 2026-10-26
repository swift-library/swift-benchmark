// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

#include "_BenchmarkCounters.h"

#if defined(__linux__)

#include <linux/perf_event.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

int benchmark_thread_counter_open(benchmark_thread_counter_kind kind) {
  struct perf_event_attr attributes;
  memset(&attributes, 0, sizeof(attributes));
  attributes.type = PERF_TYPE_HARDWARE;
  attributes.size = sizeof(attributes);
  attributes.config = kind == benchmark_thread_counter_cycles
    ? PERF_COUNT_HW_CPU_CYCLES : PERF_COUNT_HW_INSTRUCTIONS;
  attributes.disabled = 1;
  attributes.inherit = 1;
  // Containers and hardened kernels often allow only user-mode counting.
  attributes.exclude_kernel = 1;
  attributes.exclude_hv = 1;
  long counter = syscall(SYS_perf_event_open, &attributes, 0, -1, -1, 0);
  if (counter < 0) {
    return -1;
  }
  if (ioctl((int)counter, PERF_EVENT_IOC_RESET, 0) != 0
      || ioctl((int)counter, PERF_EVENT_IOC_ENABLE, 0) != 0) {
    close((int)counter);
    return -1;
  }
  return (int)counter;
}

int benchmark_thread_counter_read(int counter, uint64_t *value) {
  return read(counter, value, sizeof(*value)) == (ssize_t)sizeof(*value) ? 0 : -1;
}

void benchmark_thread_counter_close(int counter) {
  ioctl(counter, PERF_EVENT_IOC_DISABLE, 0);
  close(counter);
}

#else

int benchmark_thread_counter_open(benchmark_thread_counter_kind kind) {
  (void)kind;
  return -1;
}

int benchmark_thread_counter_read(int counter, uint64_t *value) {
  (void)counter;
  (void)value;
  return -1;
}

void benchmark_thread_counter_close(int counter) {
  (void)counter;
}

#endif
