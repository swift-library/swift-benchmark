# Release Guide

The [Versioning and Release policy](../Architecture/VersioningAndRelease.md)
owns compatibility and acceptance requirements.

1. Review shipped behavior, dependencies, incorporated-source notices and the
   supported system generations. Select the version in CLIVersion.current and
   add its nonempty CHANGELOG entry.
2. Run `Scripts/validate-version` and `Scripts/check`. Review the native and CI
   compiler/OS evidence. Run the iOS consumer gate on each selected system
   generation and retain its exact simulator/runtime results.
3. Commit the candidate, rerun release checks on that clean revision, and push
   it. Validate a fresh consumer from the remote revision, including macros,
   plugin-generated hosts, structured reports and baseline checks.
4. Create and push `vVERSION` at the accepted commit. Validate a fresh consumer
   with the next-minor SemVer requirement before publishing.
5. Dispatch the Release workflow with the existing tag. Its validation jobs run
   with read permissions; publication checks the accepted commit and promotes
   the matching draft with release notes and evidence.
6. Attach additional native/simulator evidence for that same commit and record
   the final release URL. Keep source tags and existing evidence bytes intact.

Retry a failed publication for unchanged source and accepted evidence. If a
draft has conflicting notes or bytes, review its provenance before repairing
that unpublished draft. Published source corrections use a new version.

Temporary consumer packages, logs and provenance belong under ignored `.build`
paths. Run-specific versions, device identifiers and workstation paths belong
in evidence, not package policy or reusable scripts.

`Scripts/validate-consumer --revision COMMIT --output NEW_DIRECTORY --ios`
creates an independent consumer from the remote candidate, exercises native
library/macro behavior and the no-host plugin, checks report/baseline behavior
and runs tests on each declared iOS generation. It selects installed runtimes,
creates temporary devices and removes those devices after testing. Its fixture
declares the iOS deployment floor in Package.swift.

After tagging, use `--version VERSION` in place of `--revision COMMIT` and a new
output directory to validate the next-minor dependency requirement. Keep the
resulting lockfile, logs, simulator results and provenance with release evidence.
