#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${1:-release}"
if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
    echo "Usage: ./scripts/build-app.sh [release|debug]" >&2
    exit 1
fi
SIGNING_KIND="Apple Development"
SIGNING_OPTIONS=(--timestamp=none)
if [[ "$CONFIGURATION" == "release" ]]; then
    SIGNING_KIND="Developer ID Application"
    SIGNING_OPTIONS=(--options runtime --timestamp)
fi
SIGNING_IDENTITY="${DISKLENS_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning |
        awk -v kind="$SIGNING_KIND" 'index($0, "\"" kind ":") { print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" && "$CONFIGURATION" == "release" ]]; then
    echo "A Developer ID Application identity is required for release builds." >&2
    exit 1
fi
swift build -c "$CONFIGURATION" -j 4
BINARY_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/DiskLens.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY_DIR/DiskLens" "$APP_DIR/Contents/MacOS/.DiskLens.next"
# Replace the inode atomically, so rebuilding never truncates a running executable.
mv -f "$APP_DIR/Contents/MacOS/.DiskLens.next" "$APP_DIR/Contents/MacOS/DiskLens"
if [[ "$CONFIGURATION" == "release" ]]; then
    xcrun strip -S -x "$APP_DIR/Contents/MacOS/DiskLens"
    if strings -a "$APP_DIR/Contents/MacOS/DiskLens" | grep -F "$PROJECT_DIR" >/dev/null; then
        echo "Release binary contains the local project path." >&2
        exit 1
    fi
fi
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP_DIR/Contents/Resources/"
if [[ -f Resources/StorageMasterIcon.icns ]]; then
    cp Resources/StorageMasterIcon.icns "$APP_DIR/Contents/Resources/StorageMasterIcon.icns"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "No Apple Development identity found; using ad-hoc signing." >&2
    codesign --force --deep --sign - "$APP_DIR"
elif ! codesign --force --deep "${SIGNING_OPTIONS[@]}" --sign "$SIGNING_IDENTITY" "$APP_DIR"; then
    codesign --force --deep --sign - "$APP_DIR"
    echo "Certificate signing failed; an ad-hoc signature was restored. Unlock your keychain and retry." >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
    SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
    if [[ "$SIGNATURE_DETAILS" != *"Authority=Developer ID Application:"* ||
          "$SIGNATURE_DETAILS" != *"runtime"* ||
          "$SIGNATURE_DETAILS" != *"Timestamp="* ]]; then
        codesign --force --deep --sign - "$APP_DIR"
        echo "Release signature is missing Developer ID, hardened runtime, or secure timestamp." >&2
        exit 1
    fi
fi
echo "App ready: $APP_DIR"
