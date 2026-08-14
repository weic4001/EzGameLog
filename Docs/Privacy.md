# Privacy and Data Handling

GameLog is local-first. It does not require a GameLog account, does not upload logs to a GameLog server, and does not include product analytics or crash telemetry in the current baseline.

## What GameLog reads

- Android device metadata, process lists, Logcat streams, screenshots, and screen recordings when the user requests them.
- iOS physical-device metadata, process-filtered syslog output, pairing state, and a user-requested single-frame screenshot.
- Local symbol files selected by the user for native symbolication.
- Local session directories and user-selected export destinations.

GameLog starts the bundled device tools with explicit argument arrays. It does not silently install a system-wide ADB or iOS command-line package.

## What GameLog stores

Sessions are stored locally under:

```text
~/Library/Application Support/GameLog/Sessions/
```

A session can contain JSONL logs, structured metadata, screenshots, recordings, evidence markers, diagnostics, annotations, and an integrity manifest. The user can select another writable directory in Settings.

Session data is not automatically uploaded. Anyone who can read the chosen directory can read its contents, so use normal macOS file permissions and avoid storing sensitive sessions in shared folders.

## Redaction and exports

Export preview can redact tokens, account identifiers, email addresses, IP addresses, serial numbers, and absolute paths. Project-specific regular-expression rules can be scoped to a package or package prefix.

Redaction is a convenience, not a guarantee. Screenshots, recordings, binary attachments, stack traces, and custom fields can still contain sensitive information. Review the preview and exported archive before sharing it.

## Permissions

- Android USB/Wi-Fi debugging and device authorization are controlled by Android and the user.
- iOS requires a trusted, unlocked physical connection for the supported workflows.
- macOS may request camera permission for the system screen-capture path used by an iOS screenshot. The capture is started only after the user requests it.
- GameLog currently does not provide iOS recording or remote control.

## Deleting data

Use the session archive UI or remove the selected session directory from Finder when the app is not writing to it. Also review exported ZIPs and temporary files in any user-selected export directory. Clearing a session does not revoke device trust or remove files copied elsewhere.

## Reporting privacy issues

If you discover that a release writes outside the selected location, uploads user data, leaks secrets in an export, or bypasses a permission boundary, report it privately using [SECURITY.md](../SECURITY.md).

