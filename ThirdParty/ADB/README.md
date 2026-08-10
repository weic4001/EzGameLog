# Bundled Android Debug Bridge

GameLog bundles only the macOS `adb` executable required by its device,
Logcat, screenshot, and screen-recording workflows. The rest of Android SDK
Platform-Tools is intentionally excluded.

## Provenance

- Upstream package: Android SDK Platform-Tools for macOS
- Package revision: `35.0.1`
- ADB protocol version: `1.0.41`
- Architectures: `arm64`, `x86_64`
- Original binary SHA-256:
  `92105d0c0f006a6fbdd8a91e82b791d23e4746491062b62d5ecc34abecf9086b`
- NOTICE SHA-256:
  `eeab024d239ac3e8e1f5e0b6737793be4199390958ce7ebf03d4876f63dfa368`

The upstream `NOTICE.txt` and `source.properties` are copied into the
application bundle. Release packaging signs the embedded executable
explicitly before signing the outer application.

## Updating

When replacing `adb`:

1. Use an official macOS Universal Platform-Tools release.
2. Replace `adb`, `NOTICE.txt`, and `source.properties` together.
3. Update the version and hashes above.
4. Run `script/release_preflight.sh` through `script/package_release.sh`.
5. Test USB authorization, wireless pairing, screenshot, and recording on
   both Apple Silicon and Intel.
