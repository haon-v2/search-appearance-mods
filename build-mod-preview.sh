#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$PWD/build/Search Mod Preview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Search "$APP/Contents/MacOS/SearchModPreview"
rm -f "$APP/Contents/Resources/Curve.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Search Mod Preview</string>
<key>CFBundleDisplayName</key><string>Search Mod Preview</string>
<key>CFBundleExecutable</key><string>SearchModPreview</string>
<key>CFBundleIdentifier</key><string>local.noah.search.mod-preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>

<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Search Mod Preview. Based on Search, copyright 2026 Office Commun, MIT License.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>NSCameraUsageDescription</key><string>Websites can ask to use your camera. Search Mod Preview asks you first.</string>
<key>NSMicrophoneUsageDescription</key><string>Websites can ask to use your microphone. Search Mod Preview asks you first.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Save files you choose to download.</string>
</dict></plist>
PLIST
cp LICENSE "$APP/Contents/Resources/Search-LICENSE.txt"
cp CREDITS.md "$APP/Contents/Resources/CREDITS.md"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
