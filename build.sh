#!/bin/bash
# Builds screener.app into ./build.noindex (the .noindex suffix keeps Spotlight from
# indexing the build output, so only /Applications/screener.app shows up in Spotlight).
#
# Required environment (no default, per the project's no-fallback rule):
#   CODESIGN_IDENTITY  Identity used to sign the bundle:
#                        - a "Developer ID Application" identity (name or SHA-1) for a release or for
#                          installing on this Mac; signed with the hardened runtime and a secure timestamp.
#                          Two identities share the name "Developer ID Application: GEORGIOS MARINOS
#                          (9F9H8NCAUB)", so pass the SHA-1: 2C7D6068C232BA74073D56085DDBB04E5F14DF30
#                        - "-" for an explicit ad-hoc development build. Never install it in /Applications:
#                          an ad-hoc signature changes the app's identity and macOS drops the Screen
#                          Recording permission.
#                      List identities: security find-identity -v -p codesigning
#
# The version and build number live here (VERSION / BUILD) and are stamped into Info.plist;
# package.sh reads them from this file. BUILD must go up on every packaging run.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="screener"
SWIFT_PRODUCT="Screener"
BUNDLE_ID="com.local.screener"
VERSION="0.2.1"
BUILD="5"
MIN_MACOS="14.0"
BUILD_DIR="$SCRIPT_DIR/build.noindex"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PACKAGING_DIR="$SCRIPT_DIR/packaging/macos"
TESSDATA_LOCK="$PACKAGING_DIR/tessdata.lock"
TESSDATA_CACHE="$SCRIPT_DIR/.build/tessdata-cache"

if [ -z "$CODESIGN_IDENTITY" ]; then
    echo "ERROR: CODESIGN_IDENTITY is not set. Use a Developer ID Application identity (SHA-1)," >&2
    echo "       or \"-\" for an explicit ad-hoc development build. See the header of this script." >&2
    exit 1
fi

echo "Building $APP_NAME $VERSION (build $BUILD)..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Compile (Apple silicon; the Homebrew tesseract path in the example config is /opt/homebrew)
(cd "$SCRIPT_DIR" && swift build -c release)
BIN_DIR="$(cd "$SCRIPT_DIR" && swift build -c release --show-bin-path)"
cp "$BIN_DIR/$SWIFT_PRODUCT" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Verify the declared minimum OS (must match LSMinimumSystemVersion below)
MINOS=$(otool -l "$MACOS_DIR/$APP_NAME" | awk '/LC_BUILD_VERSION/{f=1} f && /minos/{print $2; exit}')
[ "$MINOS" = "$MIN_MACOS" ] || { echo "ERROR: binary declares minos $MINOS, expected $MIN_MACOS" >&2; exit 1; }

# Resources: example config, notices, icon
cp "$SCRIPT_DIR/config.example.json" "$RESOURCES_DIR/config.example.json"
cp "$PACKAGING_DIR/THIRD-PARTY-NOTICES.txt" "$RESOURCES_DIR/THIRD-PARTY-NOTICES.txt"
cp "$PACKAGING_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Tesseract models pinned in packaging/macos/tessdata.lock: downloaded once into .build/tessdata-cache,
# verified by SHA-256, copied into Contents/Resources/tessdata.
mkdir -p "$TESSDATA_CACHE" "$RESOURCES_DIR/tessdata"
while read -r LANG_CODE SHA URL; do
    case "$LANG_CODE" in ''|\#*) continue ;; esac
    CACHED="$TESSDATA_CACHE/$LANG_CODE.traineddata"
    if [ ! -f "$CACHED" ] || [ "$(shasum -a 256 "$CACHED" | cut -d' ' -f1)" != "$SHA" ]; then
        echo "Downloading $LANG_CODE.traineddata..."
        curl -fsSL -o "$CACHED.tmp" "$URL"
        mv "$CACHED.tmp" "$CACHED"
    fi
    ACTUAL="$(shasum -a 256 "$CACHED" | cut -d' ' -f1)"
    [ "$ACTUAL" = "$SHA" ] || { echo "ERROR: $LANG_CODE.traineddata checksum mismatch ($ACTUAL)" >&2; exit 1; }
    cp "$CACHED" "$RESOURCES_DIR/tessdata/$LANG_CODE.traineddata"
done < "$TESSDATA_LOCK"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>screener — select screen text, copy it to the clipboard</string>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
xattr -cr "$APP_BUNDLE"

# Code-sign
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "Signing ad-hoc (development build; never install it in /Applications)"
    codesign --force --sign - "$APP_BUNDLE"
else
    echo "Signing with: $CODESIGN_IDENTITY (hardened runtime, timestamped)"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --strict --verbose=1 "$APP_BUNDLE"

echo "Build successful: $APP_BUNDLE"
echo ""
echo "To run:     open $APP_BUNDLE"
echo "To install: osascript -e 'tell application id \"$BUNDLE_ID\" to quit'; rm -rf /Applications/$APP_NAME.app; ditto $APP_BUNDLE /Applications/$APP_NAME.app"
