// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

// Counts system allocator calls, and on Linux the Swift runtime's allocations
// and reference counting, in a process this library is injected into: with
// `DYLD_INSERT_LIBRARIES` on Apple platforms and `LD_PRELOAD` on Linux. The
// replacements cost time on every call even while not counting, so only a
// process that measures no time loads the library.

#if defined(__linux__)
#define _GNU_SOURCE
#endif

#include "_BenchmarkInterposer.h"

#include <dlfcn.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define BENCHMARK_INTERPOSER_COUNTERS 7

#if defined(__APPLE__)
#define BENCHMARK_INTERPOSER_COUNTS_HEAP 1
#define BENCHMARK_INTERPOSER_COUNTS_SWIFT 0
#elif defined(__linux__) && defined(__GLIBC__)
#define BENCHMARK_INTERPOSER_COUNTS_HEAP 1
#define BENCHMARK_INTERPOSER_COUNTS_SWIFT 1
#else
#define BENCHMARK_INTERPOSER_COUNTS_HEAP 0
#define BENCHMARK_INTERPOSER_COUNTS_SWIFT 0
#endif

static _Atomic bool counting;
static _Atomic uint64_t counts[BENCHMARK_INTERPOSER_COUNTERS];

static inline void add(benchmark_interposer_counter counter, uint64_t value) {
  atomic_fetch_add_explicit(&counts[counter], value, memory_order_relaxed);
}

static inline void record_allocation(const void *result, size_t size) {
  if (result != NULL) {
    add(benchmark_interposer_heap_allocations, 1);
    add(benchmark_interposer_heap_allocated_bytes, size);
  }
}

static inline void record_free(const void *pointer) {
  if (pointer != NULL) {
    add(benchmark_interposer_heap_frees, 1);
  }
}

/// A reallocation counts as an allocation of the new size and a free of the
/// old block. A failed reallocation leaves the old block allocated, except
/// that a zero-size reallocation may free it and return `NULL`.
static inline void record_reallocation(const void *old, const void *result, size_t size) {
  if (result != NULL) {
    record_allocation(result, size);
    record_free(old);
  } else if (size == 0) {
    record_free(old);
  }
}

/// Removes this library from the front of the variable that loaded it, where
/// the CLI puts it, so the processes a benchmark starts do not load it: they
/// would count nothing, and one built for another architecture fails to start.
__attribute__((constructor)) static void remove_from_environment(void) {
#if defined(__APPLE__)
  const char *name = "DYLD_INSERT_LIBRARIES";
#else
  const char *name = "LD_PRELOAD";
#endif
  const char *value = getenv(name);
  Dl_info info;
  if (value == NULL || dladdr((const void *)&remove_from_environment, &info) == 0
      || info.dli_fname == NULL) {
    return;
  }
  const char *own_name = strrchr(info.dli_fname, '/');
  own_name = own_name == NULL ? info.dli_fname : own_name + 1;
  const char *separator = strchr(value, ':');
  const char *first_end = separator == NULL ? value + strlen(value) : separator;
  const char *first_name = value;
  for (const char *character = value; character < first_end; character++) {
    if (*character == '/') {
      first_name = character + 1;
    }
  }
  size_t own_length = strlen(own_name);
  if ((size_t)(first_end - first_name) != own_length
      || strncmp(first_name, own_name, own_length) != 0) {
    return;
  }
  if (separator == NULL) {
    unsetenv(name);
    return;
  }
  char *rest = strdup(separator + 1);
  if (rest != NULL) {
    setenv(name, rest, 1);
    free(rest);
  }
}

void benchmark_interposer_start(void) {
  for (int counter = 0; counter < BENCHMARK_INTERPOSER_COUNTERS; counter++) {
    atomic_store_explicit(&counts[counter], 0, memory_order_relaxed);
  }
  atomic_store(&counting, true);
}

void benchmark_interposer_stop(void) {
  atomic_store(&counting, false);
}

uint64_t benchmark_interposer_count(benchmark_interposer_counter counter) {
  int index = (int)counter;
  bool counted = index < benchmark_interposer_swift_allocations
    ? BENCHMARK_INTERPOSER_COUNTS_HEAP : BENCHMARK_INTERPOSER_COUNTS_SWIFT;
  if (index < 0 || index >= BENCHMARK_INTERPOSER_COUNTERS || !counted) {
    return UINT64_MAX;
  }
  return atomic_load_explicit(&counts[index], memory_order_relaxed);
}

#if defined(__APPLE__)

#include <malloc/malloc.h>
#include <pthread.h>

// libmalloc's entry points call one another through their exported symbols,
// which the interposition replaces too, so one allocation can pass through
// several of these functions. Only the outermost call on a thread counts.
static pthread_key_t nesting_key;

__attribute__((constructor)) static void create_nesting_key(void) {
  pthread_key_create(&nesting_key, NULL);
}

static inline bool enter(void) {
  if (!atomic_load_explicit(&counting, memory_order_relaxed)
      || pthread_getspecific(nesting_key) != NULL) {
    return false;
  }
  pthread_setspecific(nesting_key, (void *)1);
  return true;
}

static inline void leave(bool entered) {
  if (entered) {
    pthread_setspecific(nesting_key, NULL);
  }
}

// Calls from this library to the functions it replaces reach the originals.

static void *counting_malloc(size_t size) {
  bool entered = enter();
  void *result = malloc(size);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_calloc(size_t count, size_t size) {
  bool entered = enter();
  void *result = calloc(count, size);
  if (entered) record_allocation(result, count * size);
  leave(entered);
  return result;
}

static void *counting_realloc(void *pointer, size_t size) {
  bool entered = enter();
  void *result = realloc(pointer, size);
  if (entered) record_reallocation(pointer, result, size);
  leave(entered);
  return result;
}

static void *counting_reallocf(void *pointer, size_t size) {
  bool entered = enter();
  void *result = reallocf(pointer, size);
  // A failed `reallocf` frees the old block.
  if (entered) {
    record_allocation(result, size);
    record_free(pointer);
  }
  leave(entered);
  return result;
}

static void *counting_valloc(size_t size) {
  bool entered = enter();
  void *result = valloc(size);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_aligned_alloc(size_t alignment, size_t size) {
  bool entered = enter();
  void *result = aligned_alloc(alignment, size);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static int counting_posix_memalign(void **result, size_t alignment, size_t size) {
  bool entered = enter();
  int status = posix_memalign(result, alignment, size);
  if (entered && status == 0) record_allocation(*result, size);
  leave(entered);
  return status;
}

static void counting_free(void *pointer) {
  bool entered = enter();
  if (entered) record_free(pointer);
  free(pointer);
  leave(entered);
}

static void *counting_zone_malloc(malloc_zone_t *zone, size_t size) {
  bool entered = enter();
  void *result = malloc_zone_malloc(zone, size);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_zone_calloc(malloc_zone_t *zone, size_t count, size_t size) {
  bool entered = enter();
  void *result = malloc_zone_calloc(zone, count, size);
  if (entered) record_allocation(result, count * size);
  leave(entered);
  return result;
}

static void *counting_zone_realloc(malloc_zone_t *zone, void *pointer, size_t size) {
  bool entered = enter();
  void *result = malloc_zone_realloc(zone, pointer, size);
  if (entered) record_reallocation(pointer, result, size);
  leave(entered);
  return result;
}

static void *counting_zone_valloc(malloc_zone_t *zone, size_t size) {
  bool entered = enter();
  void *result = malloc_zone_valloc(zone, size);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_zone_memalign(malloc_zone_t *zone, size_t alignment, size_t size) {
  bool entered = enter();
  void *result = malloc_zone_memalign(zone, alignment, size);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static unsigned counting_zone_batch_malloc(
  malloc_zone_t *zone, size_t size, void **results, unsigned requested) {
  bool entered = enter();
  unsigned allocated = malloc_zone_batch_malloc(zone, size, results, requested);
  if (entered) {
    add(benchmark_interposer_heap_allocations, allocated);
    add(benchmark_interposer_heap_allocated_bytes, (uint64_t)allocated * size);
  }
  leave(entered);
  return allocated;
}

static void counting_zone_batch_free(malloc_zone_t *zone, void **pointers, unsigned count) {
  bool entered = enter();
  if (entered) {
    for (unsigned index = 0; index < count; index++) {
      record_free(pointers[index]);
    }
  }
  malloc_zone_batch_free(zone, pointers, count);
  leave(entered);
}

static void counting_zone_free(malloc_zone_t *zone, void *pointer) {
  bool entered = enter();
  if (entered) record_free(pointer);
  malloc_zone_free(zone, pointer);
  leave(entered);
}

static void *counting_type_malloc(size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_malloc(size, type);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_type_calloc(size_t count, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_calloc(count, size, type);
  if (entered) record_allocation(result, count * size);
  leave(entered);
  return result;
}

static void *counting_type_realloc(void *pointer, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_realloc(pointer, size, type);
  if (entered) record_reallocation(pointer, result, size);
  leave(entered);
  return result;
}

static void *counting_type_valloc(size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_valloc(size, type);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_type_aligned_alloc(size_t alignment, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_aligned_alloc(alignment, size, type);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static int counting_type_posix_memalign(
  void **result, size_t alignment, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  int status = malloc_type_posix_memalign(result, alignment, size, type);
  if (entered && status == 0) record_allocation(*result, size);
  leave(entered);
  return status;
}

static void counting_type_free(void *pointer, malloc_type_id_t type) {
  bool entered = enter();
  if (entered) record_free(pointer);
  malloc_type_free(pointer, type);
  leave(entered);
}

static void *counting_type_zone_malloc(malloc_zone_t *zone, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_zone_malloc(zone, size, type);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_type_zone_calloc(
  malloc_zone_t *zone, size_t count, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_zone_calloc(zone, count, size, type);
  if (entered) record_allocation(result, count * size);
  leave(entered);
  return result;
}

static void *counting_type_zone_realloc(
  malloc_zone_t *zone, void *pointer, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_zone_realloc(zone, pointer, size, type);
  if (entered) record_reallocation(pointer, result, size);
  leave(entered);
  return result;
}

static void *counting_type_zone_valloc(malloc_zone_t *zone, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_zone_valloc(zone, size, type);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void *counting_type_zone_memalign(
  malloc_zone_t *zone, size_t alignment, size_t size, malloc_type_id_t type) {
  bool entered = enter();
  void *result = malloc_type_zone_memalign(zone, alignment, size, type);
  if (entered) record_allocation(result, size);
  leave(entered);
  return result;
}

static void counting_type_zone_free(malloc_zone_t *zone, void *pointer, malloc_type_id_t type) {
  bool entered = enter();
  if (entered) record_free(pointer);
  malloc_type_zone_free(zone, pointer, type);
  leave(entered);
}

// dyld replaces every other image's references to `original` with
// `replacement` when it loads this library at launch.
#define INTERPOSE(replacement, original)                                                  \
  __attribute__((used)) static const struct {                                             \
    const void *replacement_function;                                                     \
    const void *original_function;                                                        \
  } interpose_##original __attribute__((section("__DATA,__interpose"))) = {              \
    (const void *)(replacement), (const void *)(original)}

INTERPOSE(counting_malloc, malloc);
INTERPOSE(counting_calloc, calloc);
INTERPOSE(counting_realloc, realloc);
INTERPOSE(counting_reallocf, reallocf);
INTERPOSE(counting_valloc, valloc);
INTERPOSE(counting_aligned_alloc, aligned_alloc);
INTERPOSE(counting_posix_memalign, posix_memalign);
INTERPOSE(counting_free, free);
INTERPOSE(counting_zone_malloc, malloc_zone_malloc);
INTERPOSE(counting_zone_calloc, malloc_zone_calloc);
INTERPOSE(counting_zone_realloc, malloc_zone_realloc);
INTERPOSE(counting_zone_valloc, malloc_zone_valloc);
INTERPOSE(counting_zone_memalign, malloc_zone_memalign);
INTERPOSE(counting_zone_batch_malloc, malloc_zone_batch_malloc);
INTERPOSE(counting_zone_batch_free, malloc_zone_batch_free);
INTERPOSE(counting_zone_free, malloc_zone_free);
INTERPOSE(counting_type_malloc, malloc_type_malloc);
INTERPOSE(counting_type_calloc, malloc_type_calloc);
INTERPOSE(counting_type_realloc, malloc_type_realloc);
INTERPOSE(counting_type_valloc, malloc_type_valloc);
INTERPOSE(counting_type_aligned_alloc, malloc_type_aligned_alloc);
INTERPOSE(counting_type_posix_memalign, malloc_type_posix_memalign);
INTERPOSE(counting_type_free, malloc_type_free);
INTERPOSE(counting_type_zone_malloc, malloc_type_zone_malloc);
INTERPOSE(counting_type_zone_calloc, malloc_type_zone_calloc);
INTERPOSE(counting_type_zone_realloc, malloc_type_zone_realloc);
INTERPOSE(counting_type_zone_valloc, malloc_type_zone_valloc);
INTERPOSE(counting_type_zone_memalign, malloc_type_zone_memalign);
INTERPOSE(counting_type_zone_free, malloc_type_zone_free);

#elif defined(__linux__) && defined(__GLIBC__)

#include <errno.h>

// glibc's own implementations, which glibc exports for allocators that
// replace `malloc` by defining it, as this library does.
extern void *__libc_malloc(size_t size);
extern void *__libc_calloc(size_t count, size_t size);
extern void *__libc_realloc(void *pointer, size_t size);
extern void __libc_free(void *pointer);
extern void *__libc_memalign(size_t alignment, size_t size);
extern void *__libc_valloc(size_t size);
extern void *__libc_pvalloc(size_t size);

static inline bool is_counting(void) {
  return atomic_load_explicit(&counting, memory_order_relaxed);
}

void *malloc(size_t size) {
  void *result = __libc_malloc(size);
  if (is_counting()) record_allocation(result, size);
  return result;
}

void *calloc(size_t count, size_t size) {
  void *result = __libc_calloc(count, size);
  if (is_counting()) record_allocation(result, count * size);
  return result;
}

void *realloc(void *pointer, size_t size) {
  void *result = __libc_realloc(pointer, size);
  if (is_counting()) record_reallocation(pointer, result, size);
  return result;
}

void *reallocarray(void *pointer, size_t count, size_t size) {
  size_t total;
  if (__builtin_mul_overflow(count, size, &total)) {
    errno = ENOMEM;
    return NULL;
  }
  return realloc(pointer, total);
}

void free(void *pointer) {
  if (is_counting()) record_free(pointer);
  __libc_free(pointer);
}

void *memalign(size_t alignment, size_t size) {
  void *result = __libc_memalign(alignment, size);
  if (is_counting()) record_allocation(result, size);
  return result;
}

void *aligned_alloc(size_t alignment, size_t size) {
  return memalign(alignment, size);
}

int posix_memalign(void **result, size_t alignment, size_t size) {
  if (alignment % sizeof(void *) != 0 || (alignment & (alignment - 1)) != 0 || alignment == 0) {
    return EINVAL;
  }
  void *allocation = memalign(alignment, size);
  if (allocation == NULL) {
    return ENOMEM;
  }
  *result = allocation;
  return 0;
}

void *valloc(size_t size) {
  void *result = __libc_valloc(size);
  if (is_counting()) record_allocation(result, size);
  return result;
}

void *pvalloc(size_t size) {
  void *result = __libc_pvalloc(size);
  if (is_counting()) record_allocation(result, size);
  return result;
}

// The Swift runtime's implementations come after this library in lookup
// order. They are found on first use, because the runtime can call these
// functions before this library's constructors run. Calls the runtime makes
// to itself bypass these replacements, so only calls from compiled code count.

typedef void *(*swift_alloc_object_function)(const void *, size_t, size_t);
typedef void *(*swift_retain_function)(void *);
typedef void (*swift_release_function)(void *);
typedef void *(*swift_retain_n_function)(void *, uint32_t);
typedef void (*swift_release_n_function)(void *, uint32_t);

static void *next_function(void *_Atomic *slot, const char *name) {
  void *function = atomic_load_explicit(slot, memory_order_acquire);
  if (function == NULL) {
    function = dlsym(RTLD_NEXT, name);
    atomic_store_explicit(slot, function, memory_order_release);
  }
  return function;
}

void *swift_allocObject(const void *metadata, size_t size, size_t alignment_mask) {
  static void *_Atomic next;
  if (is_counting()) {
    add(benchmark_interposer_swift_allocations, 1);
    add(benchmark_interposer_swift_allocated_bytes, size);
  }
  return ((swift_alloc_object_function)next_function(&next, "swift_allocObject"))(
    metadata, size, alignment_mask);
}

void *swift_retain(void *object) {
  static void *_Atomic next;
  if (is_counting()) add(benchmark_interposer_swift_retains, 1);
  return ((swift_retain_function)next_function(&next, "swift_retain"))(object);
}

void swift_release(void *object) {
  static void *_Atomic next;
  if (is_counting()) add(benchmark_interposer_swift_releases, 1);
  ((swift_release_function)next_function(&next, "swift_release"))(object);
}

void *swift_retain_n(void *object, uint32_t count) {
  static void *_Atomic next;
  if (is_counting()) add(benchmark_interposer_swift_retains, count);
  return ((swift_retain_n_function)next_function(&next, "swift_retain_n"))(object, count);
}

void swift_release_n(void *object, uint32_t count) {
  static void *_Atomic next;
  if (is_counting()) add(benchmark_interposer_swift_releases, count);
  ((swift_release_n_function)next_function(&next, "swift_release_n"))(object, count);
}

#endif
