# Architecture

Current architecture descriptions for `swift-benchmark` live here.

- `ProductDomains.md`: product-domain map for Benchmark, Instruments,
  InstrumentsMacros, Report, diagnostics adapters, and adapter domains.
- `CapabilityMap.md`: capability-track map that groups user/tool workflows
  across product domains and points to the relevant truth documents.
- `SwiftTestingAlignment.md`: Swift Testing alignment strategy, naming/type
  mapping, and rejected coupling.
- `BenchmarkDeclarations.md`: macro-first authoring, benchmark traits,
  Dimension traits, and discovery.
- `BenchmarkExecution.md`: runner plan, execution policy, samples,
  Measurement rows, and live event stream.
- `ReportEvidence.md`: report document, baseline/budget/diff/check, and output
  contracts.
- `Dimension.md`: Dimension-first measurement and Apple-aligned input-size
  semantics.
- `Memory.md`: resident memory, allocation providers, and resource regression.
- `AppleDiagnostics.md`: current xctrace diagnostics and future MetricKit
  evidence as Report-facing Apple diagnostics.
- `WorkflowAdapters.md`: package command, CLI/plugin, Swift Testing, and
  XCTest adapters.
- `ImplementationScope.md`: current implementation snapshot, Apple/Swift
  alignment policy, gap matrix, boundary decisions, and closure order for the
  Benchmark scope.
- `Benchmark.md`: Benchmark architecture, runner scope, and Benchmark-adjacent
  product boundaries.
- `Instruments.md`: Instruments layer, Instruments macros, recorder model, and
  Apple Signpost backend boundary.
- `Report.md`: structured performance evidence, baseline/regression,
  attribution, diagnostics, fallback, and renderer boundaries.

Supporting proposals, decisions, migrations, and reference notes may be added in
separate `Docs/` subtrees later. They should not replace the current truth in
this directory.

Related implementation reference:

- `../Reference/InstrumentsAlignmentChecklist.md`: implementation
  checklist, test matrix, and report expectations for aligning code with the
  Instruments architecture.
- `../Reference/BenchmarkCompletionChecklist.md`: implementation checklist,
  test matrix, and report expectations for the Benchmark implementation goal.
Official Apple/Swift alignment belongs in the relevant architecture documents.
