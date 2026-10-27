# Metrics Architecture

## Scope / Purpose

This document owns what a Benchmark sample measures and how: the built-in
metrics, timing and counting, peak memory, custom metrics, batching, and
platform availability. Metrics belong to the Benchmark runner; Report compares
and presents them without measuring anything itself.

## Model

`Benchmark.Metric` describes a metric by name, unit (`nanoseconds`, `bytes` or
`count`), direction (`lowerIsBetter` or `higherIsBetter`) and whether baseline
comparisons judge it without a threshold of its own (`isComparedByDefault`).
Its identity is its name: reports key values by name, two descriptors with the
same name are equal, and the names of the built-in metrics are reserved.

`Sample` records an iteration, the batch size it measured, and each metric's
value per call. A sample measured over a batch reports the batch's total
divided by the batch size; peak memory is the exception and is recorded once
per step.

Built-in metrics:

| Metric | Unit | Source |
| --- | --- | --- |
| `wallClock` | nanoseconds | The runner's clock around each timed batch |
| `cpuTime` | nanoseconds | Process user plus system CPU time, `getrusage(RUSAGE_SELF)`, read outside the wall clock around the same batch |
| `instructions`, `cycles` | count | Apple: `task_inspect(TASK_INSPECT_BASIC_COUNTS)` for the whole process. Linux: `perf_event_open` user-mode hardware counters of the batch's thread and the threads it creates, synchronous workloads only. Read outside the CPU clock around the same batch |
| `contextSwitches`, `pageFaults`, `systemCalls` | count | Apple: `task_events_info`. Linux: `getrusage` context switches and page faults; no system call count |
| `diskReadBytes`, `diskWriteBytes` | bytes | macOS: `proc_pid_rusage` storage bytes. Linux: `/proc/self/io` `read_bytes` and `write_bytes` |
| `swiftAllocations` | count | Swift runtime heap allocations in the counting pass |
| `swiftAllocatedBytes` | bytes | Sizes those allocations requested |
| `swiftRetains` | count | Swift strong retains, including `retain_n` counts, in the counting pass |
| `swiftReleases` | count | Swift strong releases, including `release_n` counts, in the counting pass |
| `heapAllocations` | count | System allocator calls that returned memory, in the counting pass of a process that loaded the interposer |
| `heapAllocatedBytes` | bytes | Sizes those calls requested; a reallocation counts its new size |
| `heapNetAllocations` | count | Those allocations minus frees, which stays positive for a call that keeps memory |
| `peakMemory` | bytes | Growth of the process's footprint peak above the footprint at the start of the step |

## Step Measurement

A step measures one argument row or Dimension size of a case:

```text
row input -> footprint reading
          -> warmup calls
          -> batch calibration (automatic batching)
          -> timed samples: wall clock, CPU time, process counters and custom
             metric values per batch
          -> counting pass: one batch with the runtime hooks installed, and
             the interposer counting when it is loaded
          -> footprint reading -> peak memory sample
```

A workload with per-call setup makes each batch's inputs before the batch and
frees them after its clocks and counters are read, with no sample recording
custom metrics, so neither is measured.

Timing and counting are separate so that hooks cannot slow the timed samples.
Given the interposer library, the package workflow measures each step in two
host processes: a timing process that runs no counting pass, and a counting
process that loads the interposer, runs the warmup, then the counting pass
twice in batches of the timing process's batch size, and records the second.
The CLI adds the counting sample to the timed row, and fails the run when the
counting process counted no heap allocations, which means the library it
loaded is not a working interposer.

The runner holds a process-wide measurement gate for the whole step, from making
the row's input through the counting pass, so steps of concurrent runners never
overlap: the counting hooks are process-wide and parallel steps would disturb
each other's times. A workload must not run a benchmark runner itself.

## Allocation And Reference Counting

The counting pass replaces the Swift runtime's instrumentation hook slots
(`_swift_allocObject`, `_swift_retain`, `_swift_release`, `_swift_retain_n`,
`_swift_release_n`) with counting functions that forward to the runtime's
implementations, and sets
`_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly`
so the runtime routes releases through the slots. The slots, the original
implementations and the flag's original value are resolved once, before the
first installation, and never change; the counting functions read only trivial
values, so counting cannot re-enter itself. The runtime also sets the flag
itself when an allocation finds a replaced slot, so a thread allocating as a
counting pass ends can leave it set. Uninstalling restores the slots and then
the flag, and the runner restores the flag again before each step, so no step is
timed on the hook path. The hooks count every thread of the process, which makes
the counts exact only in a process that measures nothing else. The hooks see
only the Swift runtime's own allocations; every system allocator call, from C,
C++ and Objective-C too, is counted through the interposer (see below). A
runtime without the hook symbols leaves the Swift counting metrics out.

Linux does not use the hook slots: CI showed that routing reference counting
through them, which the runtime does whenever the switch is on, crashed in
`swift_retain` and corrupted memory in the test process. Linux counts Swift
allocations and reference counting only in a counting process, through the
interposer, which replaces `swift_allocObject`, `swift_retain`,
`swift_release`, `swift_retain_n` and `swift_release_n` and forwards to the
runtime. It counts the calls compiled code makes into the runtime; calls the
runtime makes to itself bypass the replacements, so Linux can count fewer
retains and releases than Apple platforms for the same code.

The runner's own batch loops count down in `while` loops: a range loop
allocates in unoptimized builds, and the counting pass would charge those
allocations to the workload. Allocations of the workload itself are counted as
the build produces them, so an unoptimized build can count more than an
optimized one.

## Heap Allocations And The Interposer

The interposer is a C dynamic library, the `_BenchmarkInterposer` product,
that the CLI injects into counting processes: with `DYLD_INSERT_LIBRARIES` on
Apple platforms, where it replaces `malloc` and its relatives, the
`malloc_zone_*` functions and the typed `malloc_type_*` entry points through
dyld interposing, and with `LD_PRELOAD` on Linux, where it defines glibc's
allocation functions and forwards to glibc's `__libc_*` implementations. Every
allocation in the process passes through it, from C, C++, Objective-C and the
Swift runtime. The exception is `malloc_zone_malloc_with_options` and its typed
variant on Apple platforms: they exist only from macOS 26, above the package's
deployment floor, so the interposer leaves them alone; the Swift runtime,
Foundation and the C allocation functions do not route through them. The
replacements cost time on every call even while not counting, which is why only
the counting process loads the interposer and timing never runs with it.

libmalloc's entry points call one another through their exported symbols,
which interposing replaces too, so one allocation can pass through several
replacements; a per-thread nesting guard counts only the outermost. The runner
finds the library's controls with `dlsym`, so a process without it, such as a
test process, records no heap metrics. The library removes itself from the
front of the variable that loaded it, so the processes a benchmark starts do
not inherit it.

### Allocation Sites

With `--allocation-sites`, the counting process records where allocations come
from in one more batch after the counting pass, without the Swift runtime
hooks, whose counting functions would otherwise sit inside every Swift
allocation's stack. The interposer captures each counted allocation's return
addresses with `backtrace`, leaving out its own frames, and adds them to an
open-addressing table of 16,384 stacks of up to 32 frames, mapped once and
never freed; a full table records no further distinct stacks. Stacks are
captured before the table's lock is taken. On Linux a thread-local flag keeps
what unwinding allocates out of the counts and the table, and the first unwind
runs before counting starts.

The runner symbolicates the addresses with `dladdr`, demangles Swift names
with the runtime's demangler and C++ names with `__cxa_demangle` when the
process has loaded it, drops the frames from the first runner frame down,
merges stacks that become equal, and keeps the 50 with the most allocations
as `Benchmark.AllocationSites` on the row: the batch's call count and each
stack's allocations and requested bytes. Symbols come from the host's symbol
tables, so a stripped host shows image offsets.

## Peak Memory

Platforms report only the highest footprint over the process lifetime: on
Darwin `task_info(TASK_VM_INFO)`'s `phys_footprint` and
`ledger_phys_footprint_peak`, on Linux `/proc/self/statm` and
`getrusage`'s `ru_maxrss`. The runner records `peakMemory` only when created
with `recordsPeakMemory: true`, and only when the footprint peak rose during
the step; a step whose peak stays at or below the peak the process reached
earlier records no value. The package workflow runs every step in a host
process of its own and enables it there.

## Custom Metrics

A workload records values with `Benchmark.record(_:for:)`. Each timed sample
sums the values recorded during its batch and divides by the batch size. The
first descriptor recorded for a name decides its unit, direction and
`isComparedByDefault`, and values recorded under a built-in metric's name are
ignored. Custom metrics flow into statistics, baselines, thresholds and budgets
like built-in ones; command-line amounts for them are plain numbers.

## Batching

`BatchingPolicy.automatic(targetNanoseconds:maxBatchSize:)`, the default with a
1 ms target and at most 1,000,000 calls, calibrates before the timed samples:
starting from one call, each round times a batch and grows it toward the count
that reaches the target, at least twofold and at most a hundredfold, clamped to
the maximum. Calibration batches are not recorded. `.fixed(n)` uses `n` calls
per sample. Adaptive iteration limits count each batch's whole duration.

## Platform Availability

| Metric | Darwin | Linux |
| --- | --- | --- |
| `wallClock`, `cpuTime` | Yes | Yes |
| `instructions`, `cycles` | Where the hardware counters work | Synchronous workloads, where the kernel allows hardware counters; not yet validated on hardware that exposes them |
| `contextSwitches`, `pageFaults` | Yes | Yes |
| `systemCalls` | Yes | No |
| `diskReadBytes`, `diskWriteBytes` | macOS | Yes |
| `swiftAllocations`, `swiftAllocatedBytes`, `swiftRetains`, `swiftReleases` | Yes | In the counting process |
| `heapAllocations`, `heapAllocatedBytes`, `heapNetAllocations` | In the counting process | In the counting process, with glibc |
| `peakMemory` | Yes, in an isolated step | Yes, in an isolated step |

A metric a platform cannot measure is absent from the samples, never reported
as zero; comparisons skip metrics either side lacks.

`Benchmark.Metric.isComparedByDefault` marks the metrics a baseline comparison
judges without a threshold of its own. Context switches, page faults, system
calls and disk bytes move with the rest of the machine as much as with the
code, so they are reported but judged only when a threshold or budget names
them; every other built-in metric and every custom metric unless declared
otherwise is judged by default.

## Acceptance

- Batching, CPU time, counting, peak memory, custom metric descriptors,
  concurrent runners, calibration clamping and adaptive limits
  (`BenchmarkMeasurementTests`).
- Wall-clock accuracy for a known duration and sub-microsecond workloads timed
  over the calibration target (`MeasurementPrecisionTests`).
- Exact allocation counts and bytes for a workload with a known allocation
  pattern, measured in an isolated host process, and with the interposer
  exact heap counts, bytes and unfreed allocations for workloads with known
  allocations, and a workload that starts a process (package workflow tests).
- Timing and counting processes record only their own metrics, and the CLI
  adds counting samples to the timed row of their step (`BenchmarkHostTests`).
- Allocation sites name the allocating benchmark function with exact totals
  and leave out the runner (package workflow tests), and reach the JSON,
  console, Markdown and speedscope outputs (`ReportDocumentTests`).
