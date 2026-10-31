#!/bin/bash
# Builds dist/Downstage Find.app: a native window that finds Downstage devices. No Python and no server inside.
#   build.sh [version]   version defaults to today, like 2026.10.31
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PROJECT="$(dirname "$HERE")"
# built in a temp folder: macOS tags files under Documents, and codesign refuses tagged files
NAME="Downstage Find"; BID=com.downstagesystems.find
STAGE="$(mktemp -d)"; APP="$STAGE/$NAME.app"; OUT="${DOWNSTAGE_OUT:-$PROJECT/dist}"
VER="${1:-$(date +%Y.%-m.%-d)}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos11 -framework Cocoa -framework WebKit "$HERE/main.swift" -o "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>$BID</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VER</string>
<key>CFBundleVersion</key><string>$VER</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Downstage Find looks for Downstage devices on your network.</string>
<key>NSBonjourServices</key><array><string>_downstage._tcp</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict></plist>
PL
cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/"
rsync -a --exclude .DS_Store "$PROJECT/web" "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --deep -s - --identifier "$BID" "$APP"
codesign --verify --deep --strict "$APP" && echo "signed"
mkdir -p "$OUT"
ZIP="$OUT/Downstage-Find.zip"
if [ -e "$ZIP" ]; then mv "$ZIP" "$(mktemp -d)/"; fi
if [ -e "$OUT/$NAME.app" ]; then mv "$OUT/$NAME.app" "$(mktemp -d)/"; fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$OUT"
echo "$OUT/$NAME.app  $VER"
