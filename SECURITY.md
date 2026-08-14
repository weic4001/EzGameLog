# Security Policy

## Scope

GameLog is a local macOS application. It starts device tools, reads logs, captures user-requested evidence, and writes session archives to a local directory. It does not require a GameLog account or upload logs to a GameLog server.

The most security-sensitive areas are:

- Process argument construction for ADB and iOS tools.
- Session import, export, archive recovery, and path validation.
- Bundled executables and dynamic libraries.
- Code signing, Hardened Runtime, and release packaging.
- Redaction of tokens, account identifiers, IP addresses, serial numbers, and file paths.

## Supported versions

The latest `main` branch and the latest published release receive security fixes. Older releases may contain known issues in bundled tools or session import validation; update before reporting a problem when possible.

## Reporting a vulnerability

Please do not open a public issue for an exploitable vulnerability or attach unredacted device logs.

Use GitHub's private security advisory form:

<https://github.com/weic4001/EzGameLog/security/advisories/new>

Include:

- A short description and impact.
- The affected version, commit, architecture, and macOS version.
- Reproduction steps or a minimal proof of concept.
- Any relevant error output with tokens, serial numbers, paths, IPs, account identifiers, and private logs removed.
- Whether the issue affects the app, a bundled tool, a release script, or an upstream dependency.

If the advisory form is unavailable, contact the maintainer privately through GitHub and mention that the report is security-sensitive.

We aim to acknowledge a report within five business days. Timing for a fix and disclosure depends on severity, exploitability, upstream coordination, and whether a patched release is available.

## Safe handling of diagnostic data

Before sharing a session archive, use GameLog's redaction preview. A screenshot or recording can still contain sensitive UI content even when text logs are redacted. For a report, prefer a minimal synthetic fixture and include only the files needed to reproduce the issue.

## Release security checks

Maintainers should run `./script/release_preflight.sh` against the packaged app. A distributable build should use a Developer ID identity and notarization; an ad-hoc build is for local validation only.

