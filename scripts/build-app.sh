#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.1.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

RELEASE=false
UNIVERSAL=false

for arg in "$@"; do
    case "$arg" in
        --release)
            RELEASE=true
            ;;
        --universal)
            RELEASE=true
            UNIVERSAL=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--release] [--universal]"
            exit 1
            ;;
    esac
done

if [ "$RELEASE" = true ]; then
    echo -e "${YELLOW}Building (release)...${NC}"
    if [ "$UNIVERSAL" = true ]; then
        swift build -c release --arch arm64 --arch x86_64 --product Trackie
        swift build -c release --arch arm64 --arch x86_64 --product trackiectl
        BINARY_PATH=".build/apple/Products/Release"
    else
        swift build -c release --product Trackie
        swift build -c release --product trackiectl
        BINARY_PATH=".build/release"
    fi
else
    echo -e "${YELLOW}Building (debug)...${NC}"
    swift build --product Trackie
    swift build --product trackiectl
    BINARY_PATH=".build/debug"
fi

APP_DIR=".build/Trackie.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH/Trackie" "$APP_DIR/Contents/MacOS/Trackie"
# The CLI binary lives inside the bundle under its SwiftPM product name
# `trackiectl`. We intentionally do NOT also name it `trackie` here because
# on case-insensitive APFS that path collides with `Trackie`. Instead, the
# user-facing `trackie` command is installed onto $PATH by run.sh / install.sh.
cp "$BINARY_PATH/trackiectl" "$APP_DIR/Contents/MacOS/trackiectl"

# App icon
cp Resources/icons/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# SPM resource bundle (Assets.car etc.)
if [ -d "$BINARY_PATH/Trackie_Trackie.bundle" ]; then
    cp -R "$BINARY_PATH/Trackie_Trackie.bundle" "$APP_DIR/Contents/Resources/"
else
    echo -e "${YELLOW}warn: Trackie_Trackie.bundle not found — app may fail to load assets${NC}"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Trackie</string>
    <key>CFBundleIdentifier</key>
    <string>com.trackie.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Trackie</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo -e "${GREEN}built: $APP_DIR${NC}"
echo -e "${GREEN}built: $BINARY_PATH/trackiectl (installs as 'trackie')${NC}"
du -sh "$APP_DIR" | awk '{print "size: " $1}'
