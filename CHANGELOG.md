# Changelog

All notable changes to GameLog are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

This changelog starts at the current open-source baseline. Earlier local development milestones are preserved in Git history.

## [1.2.2] - 2026-08-11

### Added

- Bundled Universal ADB so Android users do not need to install Android SDK Platform-Tools separately.
- Settings support for inspecting the bundled ADB and selecting an external ADB override.
- Physical iOS device discovery, pairing diagnostics, process selection, live logs, and user-triggered screenshots.
- English localization alongside Simplified Chinese.
- iOS helper binaries and dynamic libraries with source metadata, SHA-256 records, and upstream notices.
- Release preflight checks for nested tool signing, resources, architectures, versions, hashes, and archive contents.
- Product, architecture, privacy, development, release, and contribution documentation.

### Changed

- The supported app workflow is now the Xcode `GameLog.xcodeproj` App Target; `Package.swift` remains a test/CLI compatibility entry point.
- iOS recording remains explicitly out of scope; Android recording continues to be manually started and stopped by the user.
- The app reports unsupported iOS helper architecture on Intel instead of launching incompatible binaries.

### Fixed

- Preserved local-only session behavior and redaction previews while extending the device model to include iOS platforms.

## Unreleased

Future changes should be added here before release, then moved into a dated version section. Include user-visible behavior, compatibility changes, migration notes, and any third-party binary or licensing update.

