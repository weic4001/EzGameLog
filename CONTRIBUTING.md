# Contributing to GameLog

感谢你参与 GameLog。GameLog 是一个原生 macOS 开源工具，目标是让移动游戏测试人员在一个本地会话中查看设备日志、截图、录屏和诊断结果。

This guide is intentionally concise. If a rule here conflicts with the product documentation, the current code and tests are the source of truth.

## Before you start

| Item | Requirement |
| --- | --- |
| Host | macOS 26 or later |
| IDE | Xcode 26 or later |
| Swift | Swift 6.2 or later |
| Architecture | Apple Silicon is recommended; Intel supports Android features, while the bundled iOS helpers are currently arm64-only |
| Device testing | An Android device with USB/Wi-Fi debugging, or a trusted physical iPhone for iOS work |

You do not need to install Android SDK Platform-Tools for normal development. The reviewed ADB executable is kept in `ThirdParty/ADB` and copied into the app bundle by the Xcode target. The iOS helper set is kept in `ThirdParty/iOSDeviceTools` and is currently available only on Apple Silicon.

## Local setup

```bash
git clone git@github.com:weic4001/EzGameLog.git
cd EzGameLog
open GameLog.xcodeproj
```

Use the `GameLog` scheme and `My Mac` destination in Xcode. The command-line equivalents are:

```bash
# Build and launch the Debug app
./script/build_and_run.sh

# Build, run the full Xcode test target, validate the bundle, and launch it
./script/build_and_run.sh --verify

# Run the SwiftPM-compatible test target
swift test
```

`Package.swift` is a compatibility entry point for tests and command-line workflows. The supported app workflow is the Xcode project because it contains the app target, resources, entitlements, icon, bundled tools, and shared scheme.

## Repository map

```text
Sources/GameLog/App/              App lifecycle and shared routing
Sources/GameLog/Models/           Codable domain models and preferences
Sources/GameLog/Services/         ADB, iOS, log pipeline, capture, analysis, privacy
Sources/GameLog/Stores/           Session persistence and symbol catalog
Sources/GameLog/Views/            SwiftUI screens and AppKit bridges
Tests/GameLogTests/               Unit and service tests with fake executors
ThirdParty/                       Reviewed binaries, hashes, and upstream notices
Docs/                             Product, architecture, development, and release docs
script/                           Build, package, stress, and preflight scripts
```

## Development principles

- Keep device operations behind protocols. UI code should not construct `Process` directly.
- Pass executable URLs and argument arrays to `Process`; do not build shell command strings from user input.
- Preserve Swift 6 strict-concurrency boundaries. Keep UI state on `@MainActor` and isolate persistent session writes in their existing actors.
- Keep the in-memory log buffer bounded and batch UI updates. Do not move raw log streams into a SwiftUI `List` without a measured reason.
- Treat session files, screenshots, recordings, serial numbers, IPs, tokens, and package names as user data. Never add real device material to the repository or a test fixture.
- Add a localization key to `Sources/GameLog/Resources/Localizable.xcstrings` for user-facing copy. Keep the English and Simplified Chinese catalogs complete and preserve format placeholders.
- Keep iOS recording out of the current implementation. The current iOS scope is physical-device discovery, process logs, and user-triggered screenshots.

## Tests and validation

Run the smallest relevant test first, then run the full suite before opening a pull request:

```bash
swift test
./script/build_and_run.sh --verify
```

For changes involving devices or capture, also perform a manual check with a real device:

1. Connect the device and confirm the expected authorization state.
2. Start a session for a known target package/process.
3. Confirm logs continue after the target process restarts.
4. Capture a screenshot and confirm it appears in the evidence timeline.
5. For Android-only changes, start and stop a recording and verify the exported media.
6. Export a session and inspect the redaction preview before sharing it.

For iOS changes, verify USB trust, process filtering, multiline log parsing, and screenshot permission behavior on a physical iPhone. Do not treat a simulator run as equivalent to physical-device validation.

## Making a change

1. Open or reference an issue for a non-trivial change.
2. Create a focused branch, for example `feat/ios-process-filter` or `fix/session-import-validation`.
3. Keep commits small enough to review and explain the user-facing reason in the pull request.
4. Add or update tests next to the changed behavior.
5. Update the relevant product, architecture, privacy, or release documentation.
6. Do not commit `.build`, `dist`, Xcode user data, session archives, screenshots from a real device, or signing credentials.

## Pull request checklist

- [ ] The change has a clear user or maintainer benefit.
- [ ] `swift test` passes.
- [ ] `./script/build_and_run.sh --verify` passes when app/bundle behavior changed.
- [ ] User-facing strings are localized in both supported catalogs.
- [ ] Device and media behavior has been tested with safe, redacted data.
- [ ] Third-party binaries, licenses, hashes, and notices are unchanged or updated together.
- [ ] Documentation and changelog entries describe the net change.
- [ ] The pull request contains no secrets or personal device data.

## Licensing

By contributing, you agree that your contribution is provided under the repository's [MIT License](LICENSE). Third-party components retain their upstream licenses; see [Third-Party Notices](Docs/Third-Party-Notices.md).

