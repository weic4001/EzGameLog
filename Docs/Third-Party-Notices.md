# Third-Party Notices

GameLog bundles a small set of reviewed device tools so users do not need to install separate Android or iOS command-line packages for the supported workflows. The GameLog source code is MIT-licensed; bundled components retain their own licenses.

## Bundled components

| Component | Version / revision | License | Repository files |
| --- | --- | --- | --- |
| Android Debug Bridge (`adb`) | Android SDK Platform-Tools `35.0.1` | See upstream NOTICE and included license texts | `ThirdParty/ADB/README.md`, `ThirdParty/ADB/NOTICE.txt`, `ThirdParty/ADB/source.properties` |
| `idevice_id`, `ideviceinfo`, `idevicepair`, `idevicesyslog` | libimobiledevice tool set `1.4.0` | LGPL-2.1-or-later | `ThirdParty/iOSDeviceTools/README.md`, `ThirdParty/iOSDeviceTools/Notices/` |
| libimobiledevice / glue / plist / usbmuxd / libtasn1 / libtatsu | See `source.properties` | LGPL-2.1-or-later | `ThirdParty/iOSDeviceTools/lib/`, `ThirdParty/iOSDeviceTools/Notices/` |
| OpenSSL | `3.6.3` | Apache-2.0 | `ThirdParty/iOSDeviceTools/Notices/openssl/LICENSE.txt` |

The exact source versions, architectures, and SHA-256 values are recorded in the corresponding `source.properties` files. The release preflight checks these values before packaging.

## Distribution obligations

- Keep the upstream NOTICE and license texts with every source distribution and app distribution.
- Do not claim that bundled dependencies are covered by the GameLog MIT License.
- Preserve the notices when copying the App Bundle or redistributing a release ZIP.
- Review the upstream license terms before replacing or adding a component.

## Updating a component

1. Use an official or reviewed upstream release.
2. Record the source version, architecture, and SHA-256.
3. Update the matching notice files and the component README.
4. Verify Mach-O install names and nested signing behavior.
5. Run `./script/package_release.sh` and the strict release preflight.
6. Test the affected USB, wireless, log, screenshot, and recording workflows on supported hardware.

The license files in the `ThirdParty` tree are authoritative for the exact bundled artifacts. This summary is provided for orientation and does not replace them.

