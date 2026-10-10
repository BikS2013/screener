#!/bin/bash
# Builds, signs, (optionally) notarizes, and packages screener for a GitHub release
# as both a zip archive (used by the Homebrew cask) and a drag-to-Applications disk image (.dmg),
# then writes the Homebrew cask for that version into homebrew-tap/Casks/screener.rb.
#
# Required environment:
#   CODESIGN_IDENTITY  "Developer ID Application" identity used to sign the app (pass the SHA-1:
#                      2C7D6068C232BA74073D56085DDBB04E5F14DF30, two identities share the same name).
#                      List available identities: security find-identity -v -p codesigning
#
# Optional environment:
#   NOTARY_PROFILE     Name of a notarytool keychain profile (screener-notary). When set, the zip is
#                      submitted to Apple's notary service, the ticket is stapled to the app and the zip
#                      is rebuilt; the disk image is notarized and stapled as well. Every public release
#                      must be notarized. Create the profile once from an App Store Connect API key:
#                        xcrun notarytool store-credentials screener-notary \
#                          --key <AuthKey_KEYID.p8> --key-id <KEYID> --issuer <ISSUER-ID>
#
# Usage: bash package.sh [--dmg-only]
#   --dmg-only   Skip the tests, build, app signing, zip and app notarization; reuse the existing
#                (already signed and stapled) build.noindex/screener.app and only produce the disk image.
# The version comes from build.sh (VERSION=... / BUILD=...), which also stamps Info.plist.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="screener"
VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$SCRIPT_DIR/build.sh")"
BUILD="$(sed -n 's/^BUILD="\(.*\)"$/\1/p' "$SCRIPT_DIR/build.sh")"
BUILD_DIR="$SCRIPT_DIR/build.noindex"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="$SCRIPT_DIR/dist"
ZIP_FILE="$DIST_DIR/${APP_NAME}-${VERSION}.zip"
DMG_FILE="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
SUMS_FILE="$DIST_DIR/SHA256SUMS"
CASK_FILE="$SCRIPT_DIR/homebrew-tap/Casks/$APP_NAME.rb"
INSTALL_NOTES="$SCRIPT_DIR/packaging/macos/INSTALL.txt"
DMG_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --dmg-only) DMG_ONLY=1 ;;
        *) echo "ERROR: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
    echo "ERROR: could not read VERSION / BUILD from build.sh" >&2
    exit 1
fi
if [ -z "$CODESIGN_IDENTITY" ] || [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "ERROR: CODESIGN_IDENTITY must be a Developer ID Application identity. A release package" >&2
    echo "       cannot be ad-hoc signed. See the header of this script." >&2
    exit 1
fi

echo "=== Packaging $APP_NAME v$VERSION (build $BUILD) ==="

if [ "$DMG_ONLY" -eq 1 ]; then
    echo "--dmg-only: reusing existing $APP_BUNDLE"
    [ -d "$APP_BUNDLE" ] || { echo "ERROR: $APP_BUNDLE not found; run without --dmg-only first" >&2; exit 1; }
    codesign --verify --deep --strict "$APP_BUNDLE"
    if [ -n "$NOTARY_PROFILE" ]; then
        xcrun stapler validate "$APP_BUNDLE" || { echo "ERROR: app is not stapled; run a full package first" >&2; exit 1; }
        NOTARIZED="yes (existing stapled app)"
    else
        NOTARIZED="no (NOTARY_PROFILE not set)"
    fi
else
    # Step 1: Tests (a release is never packaged from a red tree)
    echo "Running test suite..."
    (cd "$SCRIPT_DIR" && swift test)

    # Step 2: Build + sign (build.sh honours CODESIGN_IDENTITY)
    bash "$SCRIPT_DIR/build.sh"

    # Step 3: Verify the signature is a Developer ID signature with the hardened runtime
    echo "Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    codesign -dvv "$APP_BUNDLE" 2>&1 | grep -q "Authority=Developer ID Application" \
        || { echo "ERROR: bundle is not signed with a Developer ID Application identity" >&2; exit 1; }
    codesign -d --verbose=2 "$APP_BUNDLE" 2>&1 | grep -q "flags=.*runtime" \
        || { echo "ERROR: hardened runtime is not enabled" >&2; exit 1; }

    make_zip() {
        rm -f "$ZIP_FILE"
        mkdir -p "$DIST_DIR"
        # ditto preserves bundle metadata and is the archive format Apple recommends for notarization
        ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_FILE"
    }

    # Step 4: Zip
    echo "Creating $ZIP_FILE..."
    make_zip

    # Step 5: Notarize + staple (optional)
    if [ -n "$NOTARY_PROFILE" ]; then
        echo "Submitting to Apple notary service (profile: $NOTARY_PROFILE)..."
        xcrun notarytool submit "$ZIP_FILE" --keychain-profile "$NOTARY_PROFILE" --wait
        echo "Stapling ticket..."
        xcrun stapler staple "$APP_BUNDLE"
        xcrun stapler validate "$APP_BUNDLE"
        echo "Rebuilding zip with stapled app..."
        make_zip
        NOTARIZED="yes"
    else
        NOTARIZED="no (NOTARY_PROFILE not set)"
    fi

    # Step 6: Gatekeeper assessment (informational: un-notarized apps are rejected on download)
    echo "Gatekeeper assessment:"
    spctl --assess --type execute --verbose=2 "$APP_BUNDLE" 2>&1 || true
fi

# Step 7: Disk image (drag-to-Applications, with the install notes)
echo "Creating $DMG_FILE..."
DMG_STAGE="$BUILD_DIR/dmg-root"
rm -rf "$DMG_STAGE" "$DMG_FILE"
mkdir -p "$DMG_STAGE" "$DIST_DIR"
ditto "$APP_BUNDLE" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$INSTALL_NOTES" "$DMG_STAGE/INSTALL.txt"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO -quiet "$DMG_FILE"
rm -rf "$DMG_STAGE"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_FILE"
codesign --verify --verbose=1 "$DMG_FILE"
if [ -n "$NOTARY_PROFILE" ]; then
    echo "Submitting disk image to Apple notary service..."
    xcrun notarytool submit "$DMG_FILE" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_FILE"
    xcrun stapler validate "$DMG_FILE"
fi
echo "Gatekeeper assessment (disk image):"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_FILE" 2>&1 || true

# Step 8: SHA256
[ -f "$ZIP_FILE" ] || { echo "ERROR: $ZIP_FILE missing; run a full package first" >&2; exit 1; }
SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')
DMG_SHA256=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP_FILE")" "$(basename "$DMG_FILE")" > "$SUMS_FILE")

# Step 9: Homebrew cask for this version (copy kept in this repository; the tap repository
# biks2013-tools/homebrew-screener receives the same file, see docs/design/release-runbook.md)
mkdir -p "$(dirname "$CASK_FILE")"
cat > "$CASK_FILE" << CASK
cask "screener" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/biks2013-tools/screener/releases/download/v#{version}/screener-#{version}.zip"
  name "screener"
  desc "Menu bar app that copies the text of any screen area (English and Greek OCR)"
  homepage "https://github.com/biks2013-tools/screener"

  depends_on arch: :arm64
  depends_on formula: "tesseract"
  depends_on macos: :sonoma

  app "screener.app"

  postflight_steps do
    run "/usr/bin/osascript",
        args: [
          "-e",
          'display notification "Menu bar icon > Create Config from Example." with title "screener installed"',
        ]
  end

  uninstall quit: "com.local.screener"

  zap trash: "~/.tool-agents/screener"

  caveats <<~EOS
    First launch: open screener (menu bar icon, no Dock icon) and click
    "Create Config from Example". It writes ~/.tool-agents/screener/config.json
    and installs the Greek and English OCR data next to it.

    screener requires Screen Recording permission to read the screen:
      System Settings > Privacy & Security > Screen & System Audio Recording > enable screener
      (macOS asks on the first capture; quit and reopen screener afterwards)

    To start screener at login:
      menu bar icon > Launch at Login

    Global hotkeys (configurable in Settings, from the menu bar icon):
      Ctrl+Option+Cmd+T  — select an area on any screen and copy its text
      Ctrl+Option+Cmd+H  — recent captures

    Inside the selection overlay:
      Drag / Arrows      — select (Shift = faster, Option = fine; Space anchors, Return captures)
      T                  — text mode: arrows jump between text lines, Shift+arrows extend
      F                  — preserve the screen format / plain sequential text
      Tab                — next screen
      Esc                — cancel
  EOS
end
CASK

echo ""
echo "=== Package complete ==="
echo "Version:    $VERSION (build $BUILD)"
echo "Signed:     $CODESIGN_IDENTITY"
echo "Notarized:  $NOTARIZED"
echo "Zip:        $ZIP_FILE ($(du -h "$ZIP_FILE" | awk '{print $1}'))"
echo "Zip SHA256: $SHA256"
echo "DMG:        $DMG_FILE ($(du -h "$DMG_FILE" | awk '{print $1}'))"
echo "DMG SHA256: $DMG_SHA256"
echo "Cask:       $CASK_FILE"
echo ""
echo "To publish (docs/design/release-runbook.md):"
echo "  git tag -a v$VERSION -m \"screener $VERSION\" && git push origin main v$VERSION"
echo "  gh release create v$VERSION \"$ZIP_FILE\" \"$DMG_FILE\" \"$SUMS_FILE\" --title \"screener v$VERSION\" --notes-file <notes.md>"
echo "  Then copy $CASK_FILE into the tap repository (biks2013-tools/homebrew-screener), commit \"screener $VERSION\" and push."
