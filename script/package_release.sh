#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/GameLog.xcodeproj"
SCHEME="GameLog"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$PROJECT_ROOT/dist/GameLog.app"
BUNDLED_ADB="$APP_BUNDLE/Contents/MacOS/adb"
ADB_NOTICE="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/ADB/NOTICE.txt"
IOS_TOOLS_DIR="$APP_BUNDLE/Contents/MacOS"
IOS_LIBRARIES_DIR="$APP_BUNDLE/Contents/Frameworks"
IOS_NOTICE="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/iOSDeviceTools/NOTICE.txt"
IOS_SOURCE_PROPERTIES="$APP_BUNDLE/Contents/Resources/ThirdPartyNotices/iOSDeviceTools/source.properties"
IOS_TOOLS=(idevice_id ideviceinfo idevicepair idevicesyslog)
IOS_LIBRARIES=(
    libcrypto.3.dylib
    libimobiledevice-1.0.6.dylib
    libimobiledevice-glue-1.0.0.dylib
    libplist-2.0.4.dylib
    libssl.3.dylib
    libusbmuxd-2.0.7.dylib
)
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
DERIVED_DATA="$PROJECT_ROOT/.build/xcode-archive"
XCARCHIVE="$DIST_DIR/GameLog-$VERSION.xcarchive"
ARCHIVE_NAME="GameLog-$VERSION-macOS.zip"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
SIGNING_IDENTITY="${GAMELOG_SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${GAMELOG_NOTARY_PROFILE:-}"

cd "$PROJECT_ROOT"

mkdir -p "$DIST_DIR"
rm -rf "$XCARCHIVE" "$APP_BUNDLE"
rm -f "$ARCHIVE"

/usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$XCARCHIVE" \
    -destination "generic/platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    archive

ARCHIVED_APP="$XCARCHIVE/Products/Applications/GameLog.app"
test -d "$ARCHIVED_APP"
/usr/bin/ditto "$ARCHIVED_APP" "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
test -x "$BUNDLED_ADB"
test -s "$ADB_NOTICE"
test -s "$IOS_NOTICE"
test -s "$IOS_SOURCE_PROPERTIES"
for tool in "${IOS_TOOLS[@]}"; do
    test -x "$IOS_TOOLS_DIR/$tool"
done
for library in "${IOS_LIBRARIES[@]}"; do
    test -f "$IOS_LIBRARIES_DIR/$library"
done

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    for library in "${IOS_LIBRARIES[@]}"; do
        /usr/bin/codesign \
            --force \
            --strict \
            --sign - \
            "$IOS_LIBRARIES_DIR/$library"
    done
    for tool in "${IOS_TOOLS[@]}"; do
        /usr/bin/codesign \
            --force \
            --strict \
            --sign - \
            "$IOS_TOOLS_DIR/$tool"
    done
    /usr/bin/codesign \
        --force \
        --strict \
        --options runtime \
        --sign - \
        "$BUNDLED_ADB"
    /usr/bin/codesign \
        --force \
        --strict \
        --options runtime \
        --sign - \
        "$APP_BUNDLE"
else
    for library in "${IOS_LIBRARIES[@]}"; do
        /usr/bin/codesign \
            --force \
            --strict \
            --options runtime \
            --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$IOS_LIBRARIES_DIR/$library"
    done
    for tool in "${IOS_TOOLS[@]}"; do
        /usr/bin/codesign \
            --force \
            --strict \
            --options runtime \
            --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$IOS_TOOLS_DIR/$tool"
    done
    /usr/bin/codesign \
        --force \
        --strict \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$BUNDLED_ADB"
    /usr/bin/codesign \
        --force \
        --strict \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
(
    cd "$DIST_DIR"
    /usr/bin/zip -qry -X --symlinks "$ARCHIVE_NAME" "GameLog.app"
)

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    "$PROJECT_ROOT/script/release_preflight.sh" "$APP_BUNDLE"
    echo "Created ad-hoc signed archive: $ARCHIVE"
    echo "Set GAMELOG_SIGNING_IDENTITY to a Developer ID Application certificate for distribution."
    exit 0
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    GAMELOG_REQUIRE_DEVELOPER_ID=1 \
        "$PROJECT_ROOT/script/release_preflight.sh" "$APP_BUNDLE"
    echo "Created Developer ID signed archive: $ARCHIVE"
    echo "Set GAMELOG_NOTARY_PROFILE to a notarytool keychain profile to notarize."
    exit 0
fi

/usr/bin/xcrun notarytool submit "$ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
rm -f "$ARCHIVE"
(
    cd "$DIST_DIR"
    /usr/bin/zip -qry -X --symlinks "$ARCHIVE_NAME" "GameLog.app"
)

GAMELOG_REQUIRE_DEVELOPER_ID=1 \
GAMELOG_REQUIRE_NOTARIZATION=1 \
    "$PROJECT_ROOT/script/release_preflight.sh" "$APP_BUNDLE"

echo "Created signed and notarized archive: $ARCHIVE"
