# Apple Diagnostics

## Scope / Purpose

This document owns the Apple-only diagnostics that enrich Report data:
`xcrun xctrace` recording and Instruments trace attachments. They are optional
Report data; they do not enter Benchmark core and do not redefine the
Instruments runtime.

## xctrace Recording

`run`, `check` and `trace` with `--xctrace-output <path>` launch the benchmark
host once under `xcrun xctrace record`, with `--xctrace-template` choosing the
template (`Time Profiler` by default) and `--xcrun` the `xcrun` executable.
One traced process measures every selected step so that the recording is a
single trace; `trace` also captures the timeline. The host writes its
measurement to a file the CLI names, independent of what xctrace does with the
host's standard output.

A recording that fails exits with status 30. A successful one becomes a trace
attachment on every case, with the trace path, the recording command, the tool
and the template as provenance.

## Trace Attachments

`--trace <path>` attaches an existing trace to every case, and
`--required-trace <path>` does so and fails with status 30 when the trace does
not exist. `--trace-tool`, `--trace-template` and `--trace-command` record how
the trace was produced. Attachments are `DiagnosticAttachment` values of kind
`trace` in each case report.

Report records where a trace is and how it was made; it does not parse `.trace`
internals.

## Relationship To Instruments

Instruments owns spans, events, recorders, timelines and the Signpost backend.
Spans recorded through Signpost appear in an xctrace recording; timeline
attribution in the report comes from the in-process timeline, not from the
trace. Neither path leaks Signpost or xctrace concepts into Benchmark core.

## Acceptance

- xctrace record commands and their provenance, standard output routing and
  failure reporting (`AppleDiagnosticsTests`).
- Trace attachments on every case, and failure for a missing required trace
  (`BenchmarkHostTests`, `BenchmarkCommandTests`).
- Traced commands launching one measuring host process (package workflow
  tests).
