---
description: Route swift-benchmark changes to the owning architecture documents and keep its Instruments, Benchmark, Report and macro layers separate.
---
# swift-benchmark Agent Guide

## Task Route

- Read the owning architecture document before changing a layer:
  `Documentation/Architecture/Instruments.md` for Instruments,
  `ProductDomains.md` for product boundaries, `Benchmark.md` for the runner,
  and `Report.md` for reports, baselines, attribution, diagnostics adapters and
  renderers.
- When a change affects user-facing usage, update `README.md` and
  `Documentation/UsageManual.md` in the same change.
- After renaming or moving macro files, run `swift package clean` before
  building.
- For documentation changes, search the changed documents for reintroduced
  Signpost-first public wording.

## Layering

- Keep runtime APIs in `Sources/Instruments`, macro expansion in
  `Sources/InstrumentsMacro`, and the runner in the Benchmark product.
- Signpost is the Apple backend inside Instruments, not a product domain. Keep
  `OSSignposter`, `os_signpost`, signpost IDs, subsystem and category wiring and
  Apple imports behind `SignpostRecorder`; unsupported platforms compile through
  the disabled fallback.
- Macros expand to Instruments runtime APIs, never to Apple signpost APIs.
  `@Instrumented` and `@Span` must instrument function bodies; do not ship an
  attached macro that compiles without instrumenting.
- Do not keep legacy Signpost macros or APIs as public compatibility surfaces.
- Benchmark and Instruments do not depend on each other's internals;
  cross-layer attribution goes through Report-facing adapters over public APIs.
  Plugin-only helpers stay out of runtime targets.

## Licensing

- Change `LICENSE.txt`, `NOTICE` or the README license section only when asked.
- Start new source files with the SPDX header
  `// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception`, and keep
  third-party license and notice lines when copying or adapting code.
