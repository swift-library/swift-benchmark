# Release

Release status: partly manual; [Scripts/check](../../Scripts/check) provides
local validation and [Scripts/validate-consumer](../../Scripts/validate-consumer)
provides remote consumer acceptance.

Version rules for swift-benchmark, covering tags, release timing, choosing the
next version and the changelog, are in
[VERSIONING](https://github.com/swift-library/.github/blob/master/VERSIONING.md).
This document records the repository's release facts and mechanics and does not
restate those rules.

## Components and Version Sources

| Shipped component | Version meaning | Version source | Mirrors and derived fields | Update and read-only check |
| --- | --- | --- | --- | --- |
| All library products, both CLI products and the command plugin | Package release version | `CLIVersion.current` in [Sources/BenchmarkCLI/CLIVersion.swift](../../Sources/BenchmarkCLI/CLIVersion.swift), named by `version_file` in [`.github/release.json`](../../.github/release.json) | README/UsageManual pins and CLI/plugin version output; [CHANGELOG.md](../../CHANGELOG.md) records release notes. | [.github/release.json](../../.github/release.json) selects validation through `Scripts/check`. |

## Compatibility Surface

Compatibility includes public Swift APIs and macros, discovery and plugin
behavior, CLI options and exit codes, Report JSON, and compiler/platform requirements.

Core APIs compile for the declared Apple platforms. Xctrace orchestration uses
a desktop host; other platforms receive a command-unavailable result from the
default process runner. Portable recording and diagnostic fallbacks retain
their documented behavior.

## Dependencies and Verified Combinations

The package requires Swift 6.0, iOS 18 or macOS 15. The maintained system window
covers iOS 18/26/27 and macOS 15/26/27. CI tests Swift 6.0 on macOS 15 and
Swift 6.3 on macOS 26; strict formatting runs separately. Native macOS 27 and
the maintained iOS simulator generations are additional release checks.

## Derived Metadata and Drift Checks

`Scripts/check` checks README/UsageManual pins, formatting, Swift tests, release
builds, both CLI products and the command plugin. It reads the version file and
pattern from `.github/release.json` and checks both CLI products' and the command
plugin's `--version` output against the declared version.

## Candidate, Acceptance and Publication

`Scripts/validate-consumer --revision COMMIT --output NEW_DIRECTORY --ios`
creates an independent consumer from the remote candidate, exercises native
library/macro behavior and the no-host plugin, verifies discovery of library and
Swift Testing declarations, checks report/baseline behavior
and runs tests on each declared iOS generation. It selects installed runtimes,
creates temporary devices and removes those devices after testing. Its fixture
declares the iOS deployment floor in Package.swift.
The harness verifies the selected remote source before enabling its macros for
the unattended Xcode build. Macro trust is scoped to that build command.

After tagging, use `--version VERSION` in place of `--revision COMMIT` and a new
output directory to validate the next-minor dependency requirement.

## Evidence Reuse and Invalidation

Evidence belongs in `.build/release-validation`. `Scripts/check` records the
source commit and tree, OS, Swift/Xcode/SDK versions, validation-script hash and
completed check scopes in `provenance.json`.

`Scripts/validate-consumer` records the selected dependency and dependency pins,
lockfile hash, consumer-manifest and checker hashes, toolchain and simulator
details, and check exit statuses in its output directory's `provenance.json`.
Keep the resulting lockfile, logs, simulator results and provenance with release
evidence.

## Entry Points and Artifact Retention

| Operation | Existing command or explicit manual procedure | Required access |
| --- | --- | --- |
| Version update and check | Update: Not established. Check: `Scripts/check`. | Local worktree and Swift/Xcode tools. |
| Candidate validation and build | `Scripts/check`; `Scripts/validate-consumer --revision COMMIT --output NEW_DIRECTORY --ios`. | Local worktree, Swift/Xcode tools, remote source access and installed iOS runtimes. |
| Status and interrupted-run recovery | Not established. | Not established. |
| Acceptance and publication | Run [`Release`](../../.github/workflows/release.yml) with the accepted tag; it validates the tag and publishes the GitHub release. After tagging, `Scripts/validate-consumer --version VERSION --output NEW_DIRECTORY --ios` validates the next-minor dependency requirement. | Swift/Xcode tools, remote source access and installed iOS runtimes; repository write access to run workflows |
| Cleanup | `Scripts/validate-consumer` removes its temporary simulator devices after testing. | Xcode simulator tools. |

Temporary consumer packages, logs and provenance belong under ignored `.build`
paths. Run-specific versions, device identifiers and workstation paths belong
in evidence, not package policy or reusable scripts.
