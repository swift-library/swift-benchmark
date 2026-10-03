# Changelog

## 0.1.0

- Instruments spans, events, function/initializer macros and recorder context
  support runtime instrumentation with Apple Signpost and portable fallbacks.
- Benchmark provides Swift Testing and native declarations, argument rows,
  discovery, warmup, fixed/adaptive measurement and structured event streams.
- Report provides JSON evidence, baselines, budgets, Dimension curves, timeline
  attribution, memory/allocation adapters and macOS xctrace orchestration.
- The SwiftPM command plugin supports package discovery and generated hosts in
  Debug and Release configurations, with C modulemap dependency support.
- Both CLI products and the plugin expose the same `--version` value.
- Macro expansion assertions report failures through Swift Testing.
- The package uses Apache License 2.0 with the Swift Runtime Library Exception.

The supported system window is iOS 18/26/27 and macOS 15/26/27. Swift tools 6.0
is the declared compiler minimum. Executable-only benchmark declarations use
the advanced host override; private/fileprivate Testing bridge declarations
receive diagnostics. MetricKit integration is an optional future diagnostics
capability.
