# Documentation

This tree contains repository-level documentation for `swift-benchmark`.

- `Architecture/`: current architecture truth for maintainers.
- `Proposals/`: design-in-progress that is not accepted truth.
- `Decisions/`: accepted decisions and ADR-style records.
- `Migrations/`: records of accepted semantic shifts and compatibility
  boundaries.
- `Archive/`: retired or superseded historical material.
- `Reference/`: durable implementation checklists and detailed reference
  material that supports the current architecture.
- `Findings.md`: observed implementation findings that are not yet accepted
  architecture truth.

User-facing package usage is split by depth: the root `README.md` is the
quick-start and best-practice entrypoint, while `Documentation/UsageManual.md` is the
complete manual. Target-level API documentation should live with the SwiftPM
target it documents when DocC catalogs are added.

The six public library targets have DocC catalogs at
`Sources/<Target>/<Target>.docc/`. These own module introductions and API
reference; complete usage examples remain in the README and usage manual.

Documentation roles:

- `AGENTS.md`: maintainer and agent operating contract.
- `README.md`: repository entrypoint, quick start, and best practices.
- `Documentation/UsageManual.md`: complete user-facing package manual.
- `Documentation/README.md`: documentation router.
- `Documentation/Architecture/*`: current architecture truth.
- `Documentation/Architecture/CapabilityMap.md`: capability-track router across
  product domains, implementation phases, and acceptance evidence.
- `Documentation/Architecture/SwiftTestingAlignment.md`,
  `Documentation/Architecture/BenchmarkDeclarations.md`,
  `Documentation/Architecture/BenchmarkExecution.md`,
  `Documentation/Architecture/ReportEvidence.md`,
  `Documentation/Architecture/Dimension.md`,
  `Documentation/Architecture/Memory.md`,
  `Documentation/Architecture/AppleDiagnostics.md`, and
  `Documentation/Architecture/WorkflowAdapters.md`: major capability architecture
  documents.
- `Documentation/Proposals/*`: design-in-progress, not accepted truth.
- `Documentation/Reference/*`: durable reference material that supports accepted
  architecture.
- `Documentation/Decisions/*`: accepted decisions and ADRs.
- `Documentation/Migrations/*`: migration records and breaking semantic shifts.
- `Documentation/Archive/*`: superseded historical material.
- `Documentation/Findings.md`: observed findings to promote or retire after
  validation.

`Documentation/Architecture/*` is current truth. Proposal, decision,
migration, archive, and reference documents can support that truth, but they do
not replace it.
