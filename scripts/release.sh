#!/bin/bash
# Build, sign, notarize, and produce a DMG for Trackie.
#
# Prerequisites:
#   - Developer ID Application certificate in the login keychain
#   - ~/.env exports APPLE_APP_PASSWORD (app-specific password)
#   - create-dmg (brew install create-dmg)
#
# Usage:
#   ./scripts/release.sh
#   ./scripts/release.sh --skip-notarize     # skip the Apple round-trip for local testing
#   ./scripts/release.sh --version 0.2.0     # override the CFBundleShortVersionString

set -e
cd "$(dirname "$0")/.."

# shellcheck disable=SC1090
source ~/.env 2>/dev/null || true

APP_NAME="Trackie"
BUNDLE_ID="com.trackie.app"
SIGNING_IDENTITY="Developer ID Application: Swair Rajesh Shah (8B9YURJS4G)"
TEAM_ID="8B9YURJS4G"
APPLE_ID="swairshah@gmail.com"
ENTITLEMENTS="Sources/TrackieApp/Trackie.entitlements"

SKIP_NOTARIZE=false
VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=true; shift ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${GREEN}=== Trackie Release Build ===${NC}"

if [ "$SKIP_NOTARIZE" = false ] && [ -z "${APPLE_APP_PASSWORD:-}" ]; then
    echo -e "${RED}Error: APPLE_APP_PASSWORD not set in ~/.env${NC}"
    echo "Either export it or pass --skip-notarize for a local test build."
    exit 1
fi

if ! command -v create-dmg &>/dev/null; then
    echo -e "${YELLOW}Installing create-dmg...${NC}"
    brew install create-dmg
fi

# Clean outputs. Leave .build alone so incremental SPM caching still helps.
rm -rf dist .build/Trackie.app
mkdir -p dist

# Reuse the existing app-bundle builder with --universal so the DMG works on
# arm64 *and* x86_64. This handles SPM build, copying binaries into the .app,
# emitting Info.plist, and copying the icon.
echo -e "${YELLOW}Building universal .app via scripts/build-app.sh...${NC}"
./scripts/build-app.sh --universal

APP_PATH=".build/Trackie.app"
APP_BIN="$APP_PATH/Contents/MacOS/Trackie"
CLI_BIN="$APP_PATH/Contents/MacOS/trackiectl"

# Optional version override — rewrite CFBundleShortVersionString in-place.
if [ -n "$VERSION" ]; then
    echo -e "${YELLOW}Setting CFBundleShortVersionString to $VERSION...${NC}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
fi

# Sign the bundled CLI first; nested Mach-O binaries need a valid signature
# before we re-sign the enclosing app bundle (--deep would strip entitlements).
echo -e "${YELLOW}Signing nested CLI binary (trackiectl)...${NC}"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$CLI_BIN"

# Sign the app binary.
echo -e "${YELLOW}Signing app binary...${NC}"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BIN"

# Re-sign the bundle (hardened runtime + entitlements apply to the bundle).
echo -e "${YELLOW}Signing app bundle...${NC}"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"

echo -e "${YELLOW}Verifying signature...${NC}"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH" || true

if [ "$SKIP_NOTARIZE" = false ]; then
    echo -e "${YELLOW}Zipping app for notarization...${NC}"
    ZIP_PATH=".build/Trackie-notary.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo -e "${YELLOW}Submitting app to notarytool (this usually takes a few minutes)...${NC}"
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait

    echo -e "${YELLOW}Stapling notarization ticket to app...${NC}"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

# Build the DMG. Pull the (possibly-updated) version back out of Info.plist
# so the filename reflects what the app actually reports.
VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

echo -e "${YELLOW}Creating DMG at $DMG_PATH...${NC}"
create-dmg \
    --volname "$APP_NAME" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 190 \
    --app-drop-link 450 185 \
    --hide-extension "$APP_NAME.app" \
    "$DMG_PATH" \
    "$APP_PATH" 2>&1 || true

echo -e "${YELLOW}Signing DMG...${NC}"
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

if [ "$SKIP_NOTARIZE" = false ]; then
    echo -e "${YELLOW}Notarizing DMG...${NC}"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    echo -e "${YELLOW}Stapling DMG...${NC}"
    xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo -e "${GREEN}=== Release build complete ===${NC}"
echo -e "App: ${GREEN}$APP_PATH${NC}"
echo -e "DMG: ${GREEN}$DMG_PATH${NC}  $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
ls -lh "$DMG_PATH"
