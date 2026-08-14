# Support

GameLog is maintained as an open-source developer tool. Before opening an issue, search existing issues and read the relevant documentation:

- [README](README.md) for installation and common commands.
- [Development Guide](Docs/Development.md) for local builds and tests.
- [Privacy and Data Handling](Docs/Privacy.md) before sharing logs or media.
- [iOS Physical Device Plan](Docs/GameLog-iOS-Physical-Device-Plan.md) for current iOS boundaries.

## Where to ask

- Use a bug report for a reproducible failure.
- Use a feature request for a concrete workflow improvement.
- Use a pull request when you already have a tested implementation.
- Use [SECURITY.md](SECURITY.md) for vulnerabilities. Do not disclose exploitable issues publicly.

## What to include

Please include:

- GameLog version and commit, if known.
- macOS version and Mac architecture (`arm64` or `x86_64`).
- Device type, connection type, and authorization state.
- The exact workflow and the smallest reproducible steps.
- Relevant command output or a redacted diagnostic package.
- Whether the problem happens in Xcode, the packaged app, or both.

Remove tokens, account identifiers, email addresses, IP addresses, device serial numbers, absolute paths, customer data, and private screenshots before posting. Never attach signing certificates, provisioning profiles, keychain exports, or app-specific passwords.

## Device-specific notes

- Android uses the bundled Universal ADB by default. An external ADB can be selected in Settings for troubleshooting.
- iOS physical-device support currently requires a trusted USB connection and Apple Silicon for the bundled helper tools.
- iOS screenshots are user-triggered and may require macOS camera permission. iOS recording is not implemented in the current version.
- Protected content may appear black in screenshots; this is not necessarily a capture failure.

