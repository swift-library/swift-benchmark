# Contributing

## Development Policy

- Commit subjects must follow Conventional Commits:
  - `feat(scope): summary`
  - `fix: summary`
- Local validation:
  - `git config --local core.hooksPath .githooks`
- CI validation:
  - `.github/workflows/commit-message.yml` enforces commit subject format on PRs.

- Repository type policy: `swift-package`.
- All contributors (human and AI) must respect repository `.swift-format` when editing Swift code.
- Keep formatting consistent before commit.

## Validation and Releases

Run `Scripts/check` before submitting code/API changes. This performs version,
release-tool, strict-format, Swift test, Release build and CLI/plugin checks.

Read [Versioning and Release](Documentation/Architecture/VersioningAndRelease.md)
before changing a version, requirement, dependency or release workflow. Update
README and UsageManual when public behavior changes. CI and maintenance updates
are reviewed through pull requests.

Report vulnerabilities through the private route in [SECURITY.md](SECURITY.md).
