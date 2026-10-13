# Versioning and Release

swift-benchmark follows the [shared release standard](https://github.com/swift-library/.github/blob/master/VERSIONING.md).
`CLIVersion.current` in `Sources/BenchmarkCLI/CLIVersion.swift` declares the version
of all library products, both CLI products and the command plugin.
`CHANGELOG.md` records release notes; `.github/release.json` selects validation.

## Compatibility surface

Compatibility includes public Swift APIs and macros, discovery and plugin
behavior, CLI options and exit codes, Report JSON, and compiler/platform requirements.

## Requirements and validation

The package requires Swift 6.0, iOS 18 or macOS 15. The maintained system window
covers iOS 18/26/27 and macOS 15/26/27. CI tests Swift 6.0 on macOS 15 and
Swift 6.3 on macOS 26; strict formatting runs separately. Native macOS 27 and
the maintained iOS simulator generations are additional release checks.

Core APIs compile for the declared Apple platforms. Xctrace orchestration uses
a desktop host; other platforms receive a command-unavailable result from the
default process runner. Portable recording and diagnostic fallbacks retain
their documented behavior.

`Scripts/check` checks README/UsageManual pins, formatting, Swift tests, release
builds, both CLI products and the command plugin. The
[release guide](../Reference/ReleaseGuide.md) describes remote consumer checks
for library/macro behavior, discovery, reports and baselines.
Evidence belongs in `.build/release-validation`.
