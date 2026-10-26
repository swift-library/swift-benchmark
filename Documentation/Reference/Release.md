# Release

The shared workflows validate the package and publish releases from signed
version tags. Validation is declared in
[`.github/swift-package.json`](../../.github/swift-package.json); release
identity is declared in [`.github/release.json`](../../.github/release.json).

Version rules for swift-benchmark, covering tags, release timing, choosing the
next version and the changelog, are in
[VERSIONING](https://github.com/swift-library/.github/blob/master/VERSIONING.md).
This document records the repository's release facts and mechanics and does not
restate those rules.

## Components and Version Sources

| Shipped component | Version meaning | Version source | Mirrors and derived fields | Update and read-only check |
| --- | --- | --- | --- | --- |
| All library products, both CLI products and the command plugin | Package release version | `CLIVersion.current` in [Sources/BenchmarkCLI/CLIVersion.swift](../../Sources/BenchmarkCLI/CLIVersion.swift), named by `version_file` in [`.github/release.json`](../../.github/release.json) | README/UsageManual pins and CLI/plugin version output; [CHANGELOG.md](../../CHANGELOG.md) records release notes. | Update the declaration and its mirrors together. Shared policy validates the declaration; the `cli-plugin-version` command in [`.github/swift-package.json`](../../.github/swift-package.json) checks executable output. |

## Compatibility Surface

Compatibility includes public Swift APIs and macros, discovery and plugin
behavior, CLI options and exit codes, Report JSON, and compiler/platform requirements.

Core APIs compile for the declared Apple platforms and on Linux, and the
command plugin's package workflow runs on macOS and Linux. Xctrace
orchestration uses a desktop host; other platforms receive a
command-unavailable result from the default process runner. Portable recording
fallbacks retain their documented behavior, and metrics a platform cannot
measure are absent from samples rather than zero.

## Dependencies and Verified Combinations

| Releases | Swift | Platforms |
| --- | --- | --- |
| 0.1.x | Swift tools 6.0 or later | iOS 18, macOS 15 or later |
| 0.2.x | Swift 6.3 or later | iOS 18, macOS 15 or later |

Toolchains older than a release's minimum use the newest release that supports
them.

The package requires Swift 6.3, iOS 18 or macOS 15, including its command-line
products. The maintained system window covers iOS 18/26/27 and macOS 15/26/27.
Shared CI tests and builds release with two compilers: the minimum, Xcode
26.6 on macOS 26 with bundled Swift 6.3, and the latest release, Xcode 27.1 on
the `xcode-27` runner. Xcode 27.1, the last entry, also builds the
documentation, builds Report, BenchmarkTesting and BenchmarkXCTest for generic
iOS, and runs the CLI/plugin version command. A Swift 6.3 Linux image tests the
package, including the command plugin workflow. The latest SDKs check API availability against the deployment floors at
compile time; CI does not run on older systems.

## Validation

The required checks are `policy / policy` and `validate / result`.
[Source policy](../../.github/workflows/source-policy.yml) validates commit
signatures, Conventional Commit messages and PR titles, added-line rules, the
version declaration, changelog and Swift minimum.
[CI](../../.github/workflows/ci.yml) aggregates formatting, tests, release
builds, the Linux tests, the iOS builds, the five declared DocC targets and the
CLI/plugin version command.

The version command reads the version source and pattern from
`.github/release.json` and compares both CLI products' and the command plugin's
`--version` output with that declaration. Package tests cover instrumentation,
discovery, generated hosts, report samples, adapters, baselines and budget
failures.

Local validation commands are listed in [CONTRIBUTING.md](../../CONTRIBUTING.md).
Build outputs belong under ignored `.build/`.

## Publication

Pushing a signed `v*` tag triggers [Release](../../.github/workflows/release.yml).
Its `validate` job runs the shared package workflow on the tagged commit. After
validation succeeds, the shared release workflow verifies the signed annotated
tag, accepted commit, version declaration and changelog, then publishes the
changelog entry as GitHub release notes. Publication requires repository
contents write access.
