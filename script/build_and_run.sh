#!/usr/bin/env bash

set -euo pipefail

APP_NAME="GameLog"
BUNDLE_ID="com.kkxx.gamelog"
CONFIGURATION="Debug"
ACTION="${1:-run}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/GameLog.xcodeproj"
SCHEME="$APP_NAME"
DERIVED_DATA="$PROJECT_ROOT/.build/xcode"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
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

cd "$PROJECT_ROOT"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ "$ACTION" == "--release" ]]; then
    CONFIGURATION="Release"
fi

/usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
test -d "$BUILT_APP"
mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"
/usr/bin/ditto "$BUILT_APP" "$APP_BUNDLE"
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

# Debug builds produced by recent Xcode versions load the app body from
# GameLog.debug.dylib. An ad-hoc signature has no Team ID, so enabling the
# hardened runtime here would make library validation reject that dylib.
# Release packaging uses package_release.sh and keeps the hardened runtime.
for library in "${IOS_LIBRARIES[@]}"; do
    /usr/bin/codesign --force --sign - "$IOS_LIBRARIES_DIR/$library" >/dev/null
done
for tool in "${IOS_TOOLS[@]}"; do
    /usr/bin/codesign --force --sign - "$IOS_TOOLS_DIR/$tool" >/dev/null
done
/usr/bin/codesign --force --sign - "$BUNDLED_ADB" >/dev/null
DEBUG_DYLIB="$APP_BUNDLE/Contents/MacOS/GameLog.debug.dylib"
if [[ -f "$DEBUG_DYLIB" ]]; then
    /usr/bin/codesign --force --sign - "$DEBUG_DYLIB" >/dev/null
fi
/usr/bin/codesign --force --sign - "$APP_BUNDLE" >/dev/null

case "$ACTION" in
    --build|--release)
        echo "Built $APP_BUNDLE"
        ;;
    --verify|verify)
        /usr/bin/xcodebuild \
            -project "$PROJECT_PATH" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            -destination "platform=macOS" \
            CODE_SIGNING_ALLOWED=NO \
            test
        /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
        /usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
        test -s "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
        "$BUNDLED_ADB" version | /usr/bin/grep -q "Android Debug Bridge version"
        "$IOS_TOOLS_DIR/idevice_id" --version | /usr/bin/grep -q "idevice_id"
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")" = "1.2.2"
        /usr/bin/open -n "$APP_BUNDLE"
        for _ in {1..20}; do
            if pgrep -x "$APP_NAME" >/dev/null; then
                break
            fi
            sleep 0.25
        done
        pgrep -x "$APP_NAME" >/dev/null
        # Avoid accepting an app that only appears briefly before dyld exits.
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        echo "Verified $APP_BUNDLE"
        ;;
    --debug|debug)
        exec /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
        ;;
    --logs|logs)
        /usr/bin/open -n "$APP_BUNDLE"
        exec /usr/bin/log stream --info --style compact --predicate "process == '$APP_NAME'"
        ;;
    --telemetry|telemetry)
        /usr/bin/open -n "$APP_BUNDLE"
        exec /usr/bin/log stream --info --style compact --predicate "subsystem == '$BUNDLE_ID'"
        ;;
    --run|run)
        /usr/bin/open -n "$APP_BUNDLE"
        ;;
    *)
        echo "Usage: $0 [--run|--build|--release|--verify|--debug|--logs|--telemetry]" >&2
        exit 2
        ;;
esac
