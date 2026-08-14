#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_INFO="$PROJECT_ROOT/Resources/Info.plist"
APP_BUNDLE="${1:-$PROJECT_ROOT/dist/GameLog.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_INFO")"
EXPECTED_BUNDLE_ID="com.kkxx.gamelog"
XCARCHIVE="$PROJECT_ROOT/dist/GameLog-$VERSION.xcarchive"
ZIP_ARCHIVE="$PROJECT_ROOT/dist/GameLog-$VERSION-macOS.zip"
APP_INFO="$APP_BUNDLE/Contents/Info.plist"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/GameLog"
BUNDLED_ADB="$APP_BUNDLE/Contents/MacOS/adb"
ADB_NOTICE="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/ADB/NOTICE.txt"
ADB_SOURCE_PROPERTIES="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/ADB/source.properties"
SOURCE_ADB="$PROJECT_ROOT/ThirdParty/ADB/adb"
EXPECTED_SOURCE_ADB_SHA256="92105d0c0f006a6fbdd8a91e82b791d23e4746491062b62d5ecc34abecf9086b"
IOS_SOURCE_ROOT="$PROJECT_ROOT/ThirdParty/iOSDeviceTools"
IOS_SOURCE_PROPERTIES="$IOS_SOURCE_ROOT/source.properties"
IOS_NOTICE="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/iOSDeviceTools/NOTICE.txt"
IOS_BUNDLED_SOURCE_PROPERTIES="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/iOSDeviceTools/source.properties"
IOS_TOOLS_DIR="$APP_BUNDLE/Contents/MacOS"
IOS_LIBRARIES_DIR="$APP_BUNDLE/Contents/Frameworks"
IOS_TOOLS=(idevice_id ideviceinfo idevicepair idevicesyslog)
IOS_LIBRARIES=(
    libcrypto.3.dylib
    libimobiledevice-1.0.6.dylib
    libimobiledevice-glue-1.0.0.dylib
    libplist-2.0.4.dylib
    libssl.3.dylib
    libusbmuxd-2.0.7.dylib
)
REQUIRE_DEVELOPER_ID="${GAMELOG_REQUIRE_DEVELOPER_ID:-0}"
REQUIRE_NOTARIZATION="${GAMELOG_REQUIRE_NOTARIZATION:-0}"

fail() {
    echo "Release preflight failed: $*" >&2
    exit 1
}

pass() {
    echo "✓ $*"
}

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

read_property() {
    /usr/bin/awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$2"
}

test -d "$APP_BUNDLE" || fail "missing app bundle: $APP_BUNDLE"
test -f "$APP_INFO" || fail "missing app Info.plist"
test -x "$APP_EXECUTABLE" || fail "missing app executable"
test -x "$BUNDLED_ADB" || fail "missing bundled ADB executable"
test -s "$ADB_NOTICE" || fail "missing bundled ADB notices"
test -s "$ADB_SOURCE_PROPERTIES" || fail "missing bundled ADB source.properties"
test -x "$SOURCE_ADB" || fail "missing managed ADB source binary"
test -s "$IOS_SOURCE_PROPERTIES" || fail "missing iOS device-tool source.properties"
test -s "$IOS_NOTICE" || fail "missing bundled iOS device-tool notices"
test -s "$IOS_BUNDLED_SOURCE_PROPERTIES" || fail "missing bundled iOS device-tool source.properties"
for tool in "${IOS_TOOLS[@]}"; do
    test -x "$IOS_SOURCE_ROOT/bin/$tool" || fail "missing managed iOS tool: $tool"
    test -x "$IOS_TOOLS_DIR/$tool" || fail "missing bundled iOS tool: $tool"
done
for library in "${IOS_LIBRARIES[@]}"; do
    test -f "$IOS_SOURCE_ROOT/lib/$library" || fail "missing managed iOS library: $library"
    test -f "$IOS_LIBRARIES_DIR/$library" || fail "missing bundled iOS library: $library"
done
test -d "$XCARCHIVE" || fail "missing Xcode archive: $XCARCHIVE"
test -f "$ZIP_ARCHIVE" || fail "missing release ZIP: $ZIP_ARCHIVE"

SOURCE_ADB_SHA256="$(/usr/bin/shasum -a 256 "$SOURCE_ADB" | /usr/bin/awk '{print $1}')"
[[ "$SOURCE_ADB_SHA256" == "$EXPECTED_SOURCE_ADB_SHA256" ]] \
    || fail "managed ADB source hash changed: $SOURCE_ADB_SHA256"
pass "managed ADB source hash matches the reviewed binary"

for item in "${IOS_TOOLS[@]}" "${IOS_LIBRARIES[@]}"; do
    if [[ -f "$IOS_SOURCE_ROOT/bin/$item" ]]; then
        source_item="$IOS_SOURCE_ROOT/bin/$item"
    else
        source_item="$IOS_SOURCE_ROOT/lib/$item"
    fi
    expected_hash="$(read_property "$item.SHA256" "$IOS_SOURCE_PROPERTIES")"
    [[ -n "$expected_hash" ]] || fail "missing reviewed SHA-256 for $item"
    actual_hash="$(/usr/bin/shasum -a 256 "$source_item" | /usr/bin/awk '{print $1}')"
    [[ "$actual_hash" == "$expected_hash" ]] \
        || fail "managed iOS component hash changed for $item: $actual_hash"
done
pass "managed iOS device-tool hashes match the reviewed Apple Silicon binaries"

/usr/bin/plutil -lint "$SOURCE_INFO" "$APP_INFO" "$XCARCHIVE/Info.plist" >/dev/null
pass "property lists are valid"

APP_VERSION="$(read_plist "$APP_INFO" CFBundleShortVersionString)"
APP_BUILD="$(read_plist "$APP_INFO" CFBundleVersion)"
APP_BUNDLE_ID="$(read_plist "$APP_INFO" CFBundleIdentifier)"
APP_MINIMUM_SYSTEM="$(read_plist "$APP_INFO" LSMinimumSystemVersion)"
[[ "$APP_VERSION" == "$VERSION" ]] || fail "app version is $APP_VERSION, expected $VERSION"
[[ "$APP_BUILD" == "$BUILD" ]] || fail "app build is $APP_BUILD, expected $BUILD"
[[ "$APP_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] \
    || fail "bundle identifier is $APP_BUNDLE_ID, expected $EXPECTED_BUNDLE_ID"
[[ "$APP_MINIMUM_SYSTEM" == "26.0" ]] \
    || fail "minimum macOS is $APP_MINIMUM_SYSTEM, expected 26.0"
/usr/bin/grep -q "MARKETING_VERSION = $VERSION;" \
    "$PROJECT_ROOT/GameLog.xcodeproj/project.pbxproj" \
    || fail "Xcode marketing version does not match $VERSION"
/usr/bin/grep -q "CURRENT_PROJECT_VERSION = $BUILD;" \
    "$PROJECT_ROOT/GameLog.xcodeproj/project.pbxproj" \
    || fail "Xcode build number does not match $BUILD"
pass "version $VERSION ($BUILD), bundle identifier, and deployment target agree"

ARCHIVE_APP="$XCARCHIVE/Products/Applications/GameLog.app"
test -d "$ARCHIVE_APP" || fail "archive does not contain Products/Applications/GameLog.app"
ARCHIVE_VERSION="$(read_plist "$ARCHIVE_APP/Contents/Info.plist" CFBundleShortVersionString)"
ARCHIVE_BUILD="$(read_plist "$ARCHIVE_APP/Contents/Info.plist" CFBundleVersion)"
ARCHIVE_ADB="$ARCHIVE_APP/Contents/MacOS/adb"
ARCHIVE_ADB_NOTICE="$ARCHIVE_APP/Contents/Resources/ThirdPartyNotices/ADB/NOTICE.txt"
ARCHIVE_IOS_TOOLS_DIR="$ARCHIVE_APP/Contents/MacOS"
ARCHIVE_IOS_LIBRARIES_DIR="$ARCHIVE_APP/Contents/Frameworks"
ARCHIVE_IOS_NOTICE="$ARCHIVE_APP/Contents/Resources/ThirdPartyNotices/iOSDeviceTools/NOTICE.txt"
[[ "$ARCHIVE_VERSION" == "$VERSION" ]] \
    || fail "archived app version is $ARCHIVE_VERSION, expected $VERSION"
[[ "$ARCHIVE_BUILD" == "$BUILD" ]] \
    || fail "archived app build is $ARCHIVE_BUILD, expected $BUILD"
test -x "$ARCHIVE_ADB" || fail "Xcode archive does not contain bundled ADB"
test -s "$ARCHIVE_ADB_NOTICE" || fail "Xcode archive does not contain ADB notices"
test -s "$ARCHIVE_IOS_NOTICE" || fail "Xcode archive does not contain iOS device-tool notices"
for tool in "${IOS_TOOLS[@]}"; do
    test -x "$ARCHIVE_IOS_TOOLS_DIR/$tool" \
        || fail "Xcode archive does not contain iOS tool: $tool"
done
for library in "${IOS_LIBRARIES[@]}"; do
    test -f "$ARCHIVE_IOS_LIBRARIES_DIR/$library" \
        || fail "Xcode archive does not contain iOS library: $library"
done
pass "Xcode archive contains the app, Android and iOS tools, licenses, and version"

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_EXECUTABLE")"
case " $ARCHITECTURES " in
    *" arm64 "*) ;;
    *) fail "arm64 slice is missing: $ARCHITECTURES" ;;
esac
case " $ARCHITECTURES " in
    *" x86_64 "*) ;;
    *) fail "x86_64 slice is missing: $ARCHITECTURES" ;;
esac
pass "universal executable contains arm64 and x86_64"

ADB_ARCHITECTURES="$(/usr/bin/lipo -archs "$BUNDLED_ADB")"
case " $ADB_ARCHITECTURES " in
    *" arm64 "*) ;;
    *) fail "bundled ADB arm64 slice is missing: $ADB_ARCHITECTURES" ;;
esac
case " $ADB_ARCHITECTURES " in
    *" x86_64 "*) ;;
    *) fail "bundled ADB x86_64 slice is missing: $ADB_ARCHITECTURES" ;;
esac
ADB_REVISION="$(/usr/bin/sed -n 's/^Pkg.Revision=//p' "$ADB_SOURCE_PROPERTIES")"
[[ -n "$ADB_REVISION" ]] || fail "ADB revision is missing from source.properties"
ADB_VERSION_OUTPUT="$("$BUNDLED_ADB" version 2>&1)" \
    || fail "bundled ADB cannot execute"
echo "$ADB_VERSION_OUTPUT" | /usr/bin/grep -q "Android Debug Bridge version" \
    || fail "bundled executable did not identify itself as ADB"
echo "$ADB_VERSION_OUTPUT" | /usr/bin/grep -q "Version $ADB_REVISION" \
    || fail "bundled ADB version does not match source.properties ($ADB_REVISION)"
pass "bundled ADB $ADB_REVISION executes and contains arm64 and x86_64"

IOS_ARCHITECTURES="$(read_property Package.Architectures "$IOS_BUNDLED_SOURCE_PROPERTIES")"
[[ "$IOS_ARCHITECTURES" == "arm64" ]] \
    || fail "unexpected declared iOS tool architecture: $IOS_ARCHITECTURES"
for item in "${IOS_TOOLS[@]}" "${IOS_LIBRARIES[@]}"; do
    if [[ -f "$IOS_TOOLS_DIR/$item" ]]; then
        bundled_item="$IOS_TOOLS_DIR/$item"
    else
        bundled_item="$IOS_LIBRARIES_DIR/$item"
    fi
    item_architectures="$(/usr/bin/lipo -archs "$bundled_item")"
    case " $item_architectures " in
        *" arm64 "*) ;;
        *) fail "bundled iOS component has no arm64 slice ($item): $item_architectures" ;;
    esac
    if /usr/bin/otool -L "$bundled_item" | /usr/bin/grep -q '/opt/homebrew'; then
        fail "bundled iOS component retains a Homebrew load path: $item"
    fi
done
IOS_VERSION_OUTPUT="$("$IOS_TOOLS_DIR/idevice_id" --version 2>&1)" \
    || fail "bundled idevice_id cannot execute"
echo "$IOS_VERSION_OUTPUT" | /usr/bin/grep -q "idevice_id" \
    || fail "bundled executable did not identify itself as idevice_id"
pass "bundled iOS device tools execute with relative dependencies on Apple Silicon"

/usr/bin/codesign --verify --strict --verbose=2 "$BUNDLED_ADB"
/usr/bin/codesign --verify --strict --verbose=2 "$IOS_TOOLS_DIR/idevice_id"
for item in "${IOS_TOOLS[@]}"; do
    /usr/bin/codesign --verify --strict --verbose=2 "$IOS_TOOLS_DIR/$item"
done
for item in "${IOS_LIBRARIES[@]}"; do
    /usr/bin/codesign --verify --strict --verbose=2 "$IOS_LIBRARIES_DIR/$item"
done
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1)"
ADB_SIGNING_DETAILS="$(/usr/bin/codesign -dvvv "$BUNDLED_ADB" 2>&1)"
echo "$SIGNING_DETAILS" | /usr/bin/grep -q "runtime" \
    || fail "Hardened Runtime flag is missing"
echo "$ADB_SIGNING_DETAILS" | /usr/bin/grep -q "runtime" \
    || fail "bundled ADB Hardened Runtime flag is missing"
if ! echo "$SIGNING_DETAILS" | /usr/bin/grep -q "Signature=adhoc"; then
    for item in "${IOS_TOOLS[@]}"; do
        nested_details="$(/usr/bin/codesign -dvvv "$IOS_TOOLS_DIR/$item" 2>&1)"
        echo "$nested_details" | /usr/bin/grep -q "runtime" \
            || fail "Hardened Runtime flag is missing from iOS tool: $item"
    done
    for item in "${IOS_LIBRARIES[@]}"; do
        nested_details="$(/usr/bin/codesign -dvvv "$IOS_LIBRARIES_DIR/$item" 2>&1)"
        echo "$nested_details" | /usr/bin/grep -q "runtime" \
            || fail "Hardened Runtime flag is missing from iOS library: $item"
    done
fi
if /usr/bin/codesign -d --entitlements - "$APP_BUNDLE" 2>&1 \
    | /usr/bin/grep -q "com.apple.security.app-sandbox"; then
    fail "App Sandbox entitlement is enabled, but this distribution launches ADB"
fi
pass "app and nested device-tool signatures are valid, Hardened Runtime is enabled, and App Sandbox is disabled"

if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    echo "$SIGNING_DETAILS" | /usr/bin/grep -q "Signature=adhoc" \
        && fail "Developer ID was required, but the app is ad-hoc signed"
    echo "$SIGNING_DETAILS" | /usr/bin/grep -q "Authority=Developer ID Application:" \
        || fail "Developer ID Application authority is missing"
    echo "$SIGNING_DETAILS" | /usr/bin/grep -q "TeamIdentifier=not set" \
        && fail "Developer ID TeamIdentifier is missing"
    echo "$ADB_SIGNING_DETAILS" | /usr/bin/grep -q "Signature=adhoc" \
        && fail "bundled ADB is ad-hoc signed"
    echo "$ADB_SIGNING_DETAILS" | /usr/bin/grep -q "Authority=Developer ID Application:" \
        || fail "bundled ADB Developer ID Application authority is missing"
    APP_TEAM="$(echo "$SIGNING_DETAILS" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
    ADB_TEAM="$(echo "$ADB_SIGNING_DETAILS" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
    [[ "$APP_TEAM" == "$ADB_TEAM" ]] \
        || fail "app and bundled ADB use different TeamIdentifiers"
    for item in "${IOS_TOOLS[@]}"; do
        nested_details="$(/usr/bin/codesign -dvvv "$IOS_TOOLS_DIR/$item" 2>&1)"
        echo "$nested_details" | /usr/bin/grep -q "Authority=Developer ID Application:" \
            || fail "iOS tool Developer ID Application authority is missing: $item"
        nested_team="$(echo "$nested_details" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
        [[ "$APP_TEAM" == "$nested_team" ]] \
            || fail "app and iOS tool use different TeamIdentifiers: $item"
    done
    for item in "${IOS_LIBRARIES[@]}"; do
        nested_details="$(/usr/bin/codesign -dvvv "$IOS_LIBRARIES_DIR/$item" 2>&1)"
        echo "$nested_details" | /usr/bin/grep -q "Authority=Developer ID Application:" \
            || fail "iOS library Developer ID Application authority is missing: $item"
        nested_team="$(echo "$nested_details" | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
        [[ "$APP_TEAM" == "$nested_team" ]] \
            || fail "app and iOS library use different TeamIdentifiers: $item"
    done
    pass "app and all nested device tools use the same Developer ID Application identity"
else
    if echo "$SIGNING_DETAILS" | /usr/bin/grep -q "Signature=adhoc"; then
        echo "ℹ app is ad-hoc signed; suitable for local validation, not external distribution"
        echo "ℹ nested iOS tools omit Hardened Runtime locally because ad-hoc signatures have no shared Team ID"
    fi
fi

/usr/bin/unzip -tq "$ZIP_ARCHIVE"
ZIP_LIST="$(/usr/bin/unzip -Z1 "$ZIP_ARCHIVE")"
echo "$ZIP_LIST" | /usr/bin/grep -q '^GameLog\.app/' \
    || fail "release ZIP does not contain GameLog.app"
echo "$ZIP_LIST" | /usr/bin/grep -q '^GameLog\.app/Contents/MacOS/adb$' \
    || fail "release ZIP does not contain bundled ADB"
echo "$ZIP_LIST" | /usr/bin/grep -q '^GameLog\.app/Contents/Resources/ThirdPartyNotices/ADB/NOTICE\.txt$' \
    || fail "release ZIP does not contain ADB notices"
for tool in "${IOS_TOOLS[@]}"; do
    echo "$ZIP_LIST" | /usr/bin/grep -q "^GameLog\\.app/Contents/MacOS/$tool$" \
        || fail "release ZIP does not contain iOS tool: $tool"
done
for library in "${IOS_LIBRARIES[@]}"; do
    echo "$ZIP_LIST" | /usr/bin/grep -q "^GameLog\\.app/Contents/Frameworks/$library$" \
        || fail "release ZIP does not contain iOS library: $library"
done
echo "$ZIP_LIST" | /usr/bin/grep -q '^GameLog\.app/Contents/Resources/ThirdPartyNotices/iOSDeviceTools/NOTICE\.txt$' \
    || fail "release ZIP does not contain iOS device-tool notices"
if echo "$ZIP_LIST" | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    fail "release ZIP contains an unsafe path"
fi
pass "release ZIP is intact and contains only relative paths"

if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
    [[ "$REQUIRE_DEVELOPER_ID" == "1" ]] \
        || fail "notarization validation also requires GAMELOG_REQUIRE_DEVELOPER_ID=1"
    /usr/bin/xcrun stapler validate "$APP_BUNDLE"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
    pass "notarization ticket and Gatekeeper assessment are valid"
fi

echo "Release preflight passed for GameLog $VERSION ($BUILD)."
