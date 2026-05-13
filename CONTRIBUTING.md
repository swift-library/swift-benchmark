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
