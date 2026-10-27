// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

// glibc declares `dladdr` only for GNU sources, which Swift's Glibc module is
// not, so the runner looks symbols up here.
#if defined(__linux__)
#define _GNU_SOURCE
#endif

#include "_BenchmarkPlatform.h"

#include <dlfcn.h>
#include <stddef.h>

int benchmark_symbol_at(
  const void *address, const char **symbol, const char **image, uintptr_t *image_base) {
  Dl_info info;
  if (dladdr(address, &info) == 0) {
    return 0;
  }
  *symbol = info.dli_sname;
  *image = info.dli_fname;
  *image_base = (uintptr_t)info.dli_fbase;
  return 1;
}
