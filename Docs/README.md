# Documentation

This tree contains repository-level documentation for `swift-benchmark`.

- `Architecture/`: current architecture truth for maintainers.
- `Migrations/`: records of accepted semantic shifts and compatibility
  boundaries.
- `Reference/`: durable implementation checklists and detailed reference
  material that supports the current architecture.
- `Decisions/`: accepted decisions and ADR-style records.

User-facing package usage stays in the root `README.md`. Target-level API
documentation should live with the SwiftPM target it documents when DocC
catalogs are added.

Documentation roles:

- `AGENTS.md`: maintainer and agent operating contract.
- `README.md`: repository entrypoint and user-facing package manual.
- `Docs/README.md`: documentation router.
- `Docs/Architecture/*`: current architecture truth.
- `Docs/Architecture/CapabilityMap.md`: capability-track router across
  product domains, implementation phases, and acceptance evidence.
- `Docs/Architecture/SwiftTestingAlignment.md`,
  `Docs/Architecture/BenchmarkDeclarations.md`,
  `Docs/Architecture/BenchmarkExecution.md`,
  `Docs/Architecture/ReportEvidence.md`,
  `Docs/Architecture/Dimension.md`,
  `Docs/Architecture/Memory.md`,
  `Docs/Architecture/AppleDiagnostics.md`, and
  `Docs/Architecture/WorkflowAdapters.md`: major capability architecture
  documents.
- `Docs/Proposals/*`: design-in-progress, not accepted truth.
- `Docs/Reference/*`: durable reference material that supports accepted
  architecture.
- `Docs/Decisions/*`: accepted decisions and ADRs.
- `Docs/Migrations/*`: migration records and breaking semantic shifts.
- `Docs/Archive/*`: superseded historical material.
