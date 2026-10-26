# Metrics Architecture

## Scope / Purpose

This document owns what a Benchmark sample measures and how: the built-in
metrics, timing and counting, peak memory, custom metrics, batching, and
platform availability. Metrics belong to the Benchmark runner; Report compares
and presents them without measuring anything itself.

## Model

`Benchmark.Metric` describes a metric by name, unit (`nanoseconds`, `bytes` or
`count`) and direction (`lowerIsBetter` or `higherIsBetter`). Its identity is
its name: reports key values by name, two descriptors with the same name are
equal, and the names of the built-in metrics are reserved.

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
| `peakMemory` | bytes | Growth of the process's footprint peak above the footprint at the start of the step |

## Step Measurement

A step measures one argument row or Dimension size of a case:

```text
setup -> footprint reading
      -> warmup calls
      -> batch calibration (automatic batching)
      -> timed samples: wall clock and CPU time per batch, custom metric values
      -> counting pass: one batch with the runtime hooks installed
      -> footprint reading -> peak memory sample
```

Timing and counting are separate so that hooks cannot slow the timed samples.
The runner holds a process-wide measurement gate for the whole step, from setup
through the counting pass, so steps of concurrent runners never overlap: the
counting hooks are process-wide and parallel steps would disturb each other's
times.
A workload must not run a benchmark runner itself.

## Allocation And Reference Counting

The counting pass replaces the Swift runtime's instrumentation hook slots
(`_swift_allocObject`, `_swift_retain`, `_swift_release`, `_swift_retain_n`,
`_swift_release_n`) with counting functions that forward to the runtime's
implementations, and sets
`_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly`
so the runtime routes releases through the slots. The slots, the original
implementations and the flag's original value are resolved once, before the
first installation, and never change; the counting functions read only
trivial values, so counting cannot re-enter itself. The runtime also sets the
flag itself when an allocation finds a replaced slot, so a thread allocating
as a counting pass ends can leave it set. Uninstalling restores the slots and
then the flag, and the runner restores the flag again before each step, so
no step is timed on the hook path. The hooks count every thread of the process, which makes the
counts exact only in a process that measures nothing else. C and Objective-C
`malloc` allocations are not counted. A runtime without the hook symbols leaves
the counting metrics out.

Only Apple platforms count. On Linux, CI showed that routing reference
counting through the hook slots, which the runtime does whenever the switch is
on, crashed in `swift_retain` and corrupted memory in the test process. Linux
runs the counting pass's workload without hooks and records no counts.

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
first descriptor recorded for a name decides its unit and direction, and values
recorded under a built-in metric's name are ignored. Custom metrics flow into
statistics, baselines, thresholds and budgets like built-in ones; command-line
amounts for them are plain numbers.

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
| `instructions`, `cycles` | Where the hardware counters work | Synchronous workloads, where the kernel allows hardware counters |
| `contextSwitches`, `pageFaults` | Yes | Yes |
| `systemCalls` | Yes | No |
| `diskReadBytes`, `diskWriteBytes` | macOS | Yes |
| Counting metrics | Yes | No |
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
  pattern, measured in an isolated host process (package workflow tests).
