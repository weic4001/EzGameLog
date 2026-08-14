# Bundled iOS device tools

GameLog bundles the minimum `libimobiledevice` command-line tools required for
iOS physical-device discovery, pairing diagnostics, process selection, and
live logs. Screenshots use the public macOS CoreMediaIO/AVFoundation capture
path and do not use a bundled screenshot command.

## Contents

- `idevice_id` — connected-device discovery
- `ideviceinfo` — device name, model, and OS metadata
- `idevicepair` — pairing/trust diagnostics
- `idevicesyslog` — process discovery and live device logs
- The direct dynamic libraries required by those executables
- Complete upstream license texts under `Notices/`

## Provenance

- libimobiledevice `1.4.0` — LGPL-2.1-or-later
- libimobiledevice-glue `1.3.2` — LGPL-2.1-or-later
- libplist `2.7.0` — LGPL-2.1-or-later
- libusbmuxd `2.1.1` — LGPL-2.1-or-later library
- OpenSSL `3.6.3` — Apache-2.0
- libtasn1 `4.21.0` — LGPL-2.1-or-later
- libtatsu `1.0.5` — LGPL-2.1-or-later
- Source package: Homebrew bottles for Apple Silicon macOS 26
- Architectures: `arm64`

The executables load their libraries from
`@executable_path/../Frameworks`. The libraries use `@loader_path` for their
private dependencies. Release packaging signs the libraries first, then the
tools, and finally the outer application. Developer ID distribution enables
Hardened Runtime on every layer with one Team ID. Local ad-hoc validation omits
Hardened Runtime on the iOS helpers because ad-hoc signatures have no shared
Team ID for library validation.

Exact versions and SHA-256 values are recorded in `source.properties` and are
checked by `script/release_preflight.sh`.

## Compatibility boundary

The bundled iOS helper set is currently Apple Silicon only. GameLog itself and
the bundled ADB remain Universal, so Android features continue to work on Intel
Macs. On Intel, GameLog reports the iOS tools as unavailable instead of trying
to launch incompatible binaries. A reviewed x86_64 build of the same helper
set is required before iOS support can be declared Universal.

## Updating

When replacing any component:

1. Keep the tool set minimal and use reviewed upstream releases.
2. Update the matching libraries, license texts, versions, and hashes together.
3. Re-apply the relative Mach-O install names documented above.
4. Run `script/package_release.sh`, which invokes the release preflight.
5. Re-test USB trust, process listing, live logs, and screenshots on physical
   iPhones.
