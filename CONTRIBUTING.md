# Contributing

External contributions are welcome. Use a Conventional Commit PR title and
follow `.swift-format`. Maintainers follow the shared
[signing instructions](https://github.com/swift-library/.github/blob/master/MAINTENANCE.md#signing).

Use Swift 6.3 or later. Shared CI uses Xcode 26.6 on macOS 26 as its sole
compiler entry. Deployment minimums are iOS 18 and macOS 15 for all products.

Run local validation before submitting changes:

```bash
swift build
swift test
swift build -c release
xcrun swift-format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests Plugins
```

CI uses [`.github/swift-package.json`](.github/swift-package.json) for the
compiler entry, formatting paths, DocC targets and CLI/plugin version command.
Run its `commands` entries with Bash when changing the CLI or command plugin.
The required checks are `policy / policy` and `validate / result`.

Read [Release](Documentation/Reference/Release.md)
before changing compatibility, requirements or release inputs. Update README
and UsageManual when public behavior changes. Preserve source and dependency notices.
Report vulnerabilities through [SECURITY.md](SECURITY.md).
