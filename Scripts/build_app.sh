#!/usr/bin/env bash
#
# Build a double-clickable "NTFS For Mac.app" bundle from the SPM executable.
#
# Why this exists: `swift build` produces a CLI binary that happens to draw a
# SwiftUI window. Finder won't treat that as a real app (no Dock icon, no
# proper activation, occasional event-handling quirks). Bundling the binary
# into a standard .app structure with a valid Info.plist + ad-hoc code
# signature gives us a real macOS app without needing Xcode.
#
# Usage:
#   ./Scripts/build_app.sh             # release build, output in ./build
#   ./Scripts/build_app.sh --debug     # debug build (faster, larger)
#   ./Scripts/build_app.sh --install   # also copy to /Applications

set -euo pipefail

APP_NAME="NTFS For Mac"
EXECUTABLE_NAME="NTFSAccess"           # produced by `swift build`
BUNDLE_ID="dev.local.ntfsformac"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

CONFIG="release"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --debug)   CONFIG="debug" ;;
        --release) CONFIG="release" ;;
        --install) INSTALL=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Compiling Swift package ($CONFIG)..."
cd "$PROJECT_DIR"
swift build -c "$CONFIG"

BINARY_PATH="$PROJECT_DIR/.build/$CONFIG/$EXECUTABLE_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
    echo "ERROR: built binary not found at $BINARY_PATH" >&2
    exit 1
fi

echo "==> Assembling bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Bundle executable name has spaces; matches CFBundleExecutable.
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>NTFS For Mac — local build</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>NTFS For Mac uses AppleScript to request administrator authorization for mounting NTFS volumes through ntfs-3g.</string>
</dict>
</plist>
PLIST

# PkgInfo file: legacy but some tools still look for it.
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

echo "==> Ad-hoc signing..."
# Ad-hoc signing (`--sign -`) gives the binary a valid signature that LaunchServices
# accepts without an Apple Developer ID. Gatekeeper still flags it as "from an
# unidentified developer" the first time, which the user can dismiss with
# right-click → Open. Without any signature at all, modern macOS may refuse to
# launch the app at all on Apple Silicon.
codesign --sign - --force --timestamp=none --options=runtime \
    --identifier "$BUNDLE_ID" \
    "$APP_DIR"

# Quick sanity check.
codesign --verify --verbose=2 "$APP_DIR" >/dev/null 2>&1 || {
    echo "Warning: codesign verification failed (continuing)" >&2
}

# Strip any quarantine xattr the build process might have inherited so the user
# doesn't see a "downloaded from internet" warning on a locally built app.
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

if [[ "$INSTALL" -eq 1 ]]; then
    echo "==> Installing to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
    INSTALL_PATH="/Applications/$APP_NAME.app"
else
    INSTALL_PATH="$APP_DIR"
fi

echo
echo "Built: $INSTALL_PATH"
echo
echo "Launch it with one of:"
echo "  open '$INSTALL_PATH'"
echo "  Finder → double-click the bundle"
