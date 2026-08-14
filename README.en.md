# GameLog

GameLog is a native macOS tool for mobile-game testing and client development. It combines live device logs, screenshots, Android screen recordings, evidence markers, session archives, and local diagnostics in one desktop workspace.

The current baseline is `1.2.2` and targets macOS 26 or later.

## Highlights

- Bundled Universal ADB: Android users do not need to install Android SDK Platform-Tools separately.
- Physical iOS device logs and user-triggered screenshots through bundled Apple-Silicon helper tools.
- High-throughput Logcat viewing with bounded memory, filtering, search, presets, and multiple windows.
- Manual Android recording with stop-controlled duration, storage guardrails, segmented recording, and merge-on-stop.
- Session persistence and recovery, evidence timelines, redaction previews, problem packages, crash/ANR aggregation, import/export integrity manifests, regression comparison, and local symbolication.
- Local-only by default: no GameLog account, telemetry upload, or cloud archive.

## Requirements

- macOS 26+
- Xcode 26+ and Swift 6.2+ for development
- Apple Silicon for the bundled iOS helper tools; Android remains available on Intel with the Universal ADB

## Build and run

```bash
open GameLog.xcodeproj
./script/build_and_run.sh
./script/build_and_run.sh --verify
swift test
```

The supported app target is `GameLog` in `GameLog.xcodeproj`. `dist/GameLog.app` is a local build artifact and is intentionally ignored by Git.

## Device support

| Platform | Logs | Screenshot | Recording |
| --- | --- | --- | --- |
| Android physical device | Yes | Yes | Yes, user-controlled |
| Android emulator | Yes | Yes | Yes, subject to emulator behavior |
| iOS physical device | Yes | Yes, user-triggered | Planned, not implemented |
| iOS simulator | Not a supported physical-device path | Not the current target | Not implemented |

## Documentation

- [中文 README](README.md)
- [Development Guide](Docs/Development.md)
- [Release Guide](Docs/Release.md)
- [Privacy and Data Handling](Docs/Privacy.md)
- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Support](SUPPORT.md)
- [Changelog](CHANGELOG.md)
- [Third-Party Notices](Docs/Third-Party-Notices.md)
- [Product requirements](Docs/GameLog-PRD.md)
- [Technical architecture](Docs/GameLog-Technical-Architecture.md)

## License

GameLog is released under the [MIT License](LICENSE). Bundled ADB, libimobiledevice components, and their dependencies retain their upstream licenses; see [Third-Party Notices](Docs/Third-Party-Notices.md).

