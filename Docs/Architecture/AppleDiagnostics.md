# Apple Diagnostics

## Scope / Purpose

This document owns Apple-only diagnostics that enrich Report evidence. Current
implemented scope is `xcrun xctrace` artifact orchestration, trace attachment
provenance, and Signpost/trace correlation through public Report and
Instruments seams. MetricKit is future optional production diagnostics
evidence.

These diagnostics are optional Report evidence. They do not enter Benchmark
core and do not redefine Instruments runtime.

## Current Implementation Status

Current source has Report-side diagnostic attachment export, trace artifact
attachment/provenance seams, and `xcrun xctrace record` orchestration through
`XctraceRecorder`. CLI/plugin trace workflows can record a host execution,
attach the resulting `.trace`, and preserve command/template provenance in
`ReportDocument`. Public `xctrace export` XML/TOC attachments are modeled as
optional trace artifact metadata. Trace orchestration remains optional Report
diagnostics.

Current source also has MetricKit-style snapshot seams. Real MetricKit delivery
through `MXMetricManagerSubscriber` and production payload lifecycle handling are
future work, not current Benchmark closure acceptance.

## MetricKit Future Boundary

MetricKit is Apple-only and primarily online app/session scoped. It is not a
current Benchmark closure requirement and should not block portable acceptance.

Future MetricKit evidence should include:

- payload window,
- payload version,
- source/provenance metadata,
- metric names and values where available,
- unavailable/notConfigured/failed states.

Do not promise deterministic per-iteration MetricKit data.

## xctrace

`xcrun xctrace record` support is public-tool orchestration:

- run command,
- record command metadata,
- attach `.trace`,
- optionally attach public `xctrace export` XML/TOC metadata,
- preserve provenance in `ReportDocument`.

Do not parse private `.trace` internals as a stable API.

## Relationship To Instruments

Instruments runtime owns spans, events, recorders, timeline, and Signpost
backend behavior. Apple Diagnostics can attach trace artifacts to reports, and
future production diagnostics can attach MetricKit payloads, but neither path
may leak Signpost, xctrace, or MetricKit concepts into Benchmark core.

## Acceptance Evidence

- Unavailable/notConfigured/failed tests.
- xctrace unavailable/available path tests.
- Trace attachment provenance tests.
- CLI/plugin required-diagnostic exit-code tests.
