# Release Guide

Follow the [shared release procedure](https://github.com/swift-library/.github/blob/master/VERSIONING.md#release-procedure)
and [package validation requirements](../Architecture/VersioningAndRelease.md).

Temporary consumer packages, logs and provenance belong under ignored `.build`
paths. Run-specific versions, device identifiers and workstation paths belong
in evidence, not package policy or reusable scripts.

`Scripts/validate-consumer --revision COMMIT --output NEW_DIRECTORY --ios`
creates an independent consumer from the remote candidate, exercises native
library/macro behavior and the no-host plugin, checks report/baseline behavior
and runs tests on each declared iOS generation. It selects installed runtimes,
creates temporary devices and removes those devices after testing. Its fixture
declares the iOS deployment floor in Package.swift.
The harness verifies the selected remote source before enabling its macros for
the unattended Xcode build. Macro trust is scoped to that build command.

After tagging, use `--version VERSION` in place of `--revision COMMIT` and a new
output directory to validate the next-minor dependency requirement. Keep the
resulting lockfile, logs, simulator results and provenance with release evidence.
