#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$PWD/build/Search Mod Preview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Search "$APP/Contents/MacOS/SearchModPreview"
rm -f "$APP/Contents/Resources/Curve.icns"
# Keep Search’s original artwork; mods do not replace the host app icon.
ICONSET="$PWD/build/SearchModPreview.iconset"
ICONDOC="$PWD/build/AppIcon.icon"
MINIMUM="14.0"
swift Icon/icon.swift "$ICONSET" "$ICONDOC" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
ICONNAME=""
ICONCAR="build/AppIcon.car"
rm -rf "$ICONCAR"
mkdir -p "$ICONCAR"
# Full paths: actool hands the document to a helper that runs elsewhere, and
# with "build/…" it finds nothing ("Icon export exited with status 255").
if xcrun actool "$ICONDOC" --compile "$PWD/$ICONCAR" --platform macosx \
     --minimum-deployment-target "$MINIMUM" --app-icon AppIcon \
     --output-partial-info-plist "$PWD/$ICONCAR/partial.plist" > /dev/null 2>&1 \
   && [ -f "$ICONCAR/Assets.car" ]; then
  cp "$ICONCAR/Assets.car" "$APP/Contents/Resources/Assets.car"
  ICONNAME="<key>CFBundleIconName</key><string>AppIcon</string>"
else
  echo "note: actool from Xcode 26 didn't compile the icon — no Dark or Tinted style this time" >&2
fi
rm -rf "$ICONCAR" "$ICONDOC"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Search Mod Preview</string>
<key>CFBundleDisplayName</key><string>Search Mod Preview</string>
<key>CFBundleExecutable</key><string>SearchModPreview</string>
<key>CFBundleIdentifier</key><string>local.noah.search.mod-preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$(cat LOADER_VERSION)</string>
<key>CFBundleVersion</key><string>$(cat LOADER_BUILD)</string>
<key>SearchUpstreamVersion</key><string>$(cat UPSTREAM_VERSION)</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
$ICONNAME

<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppleScriptEnabled</key><true/>
<key>OSAScriptingDefinition</key><string>Search.sdef</string>
<key>NSHumanReadableCopyright</key><string>Search Mod Preview. Based on Search, copyright 2026 Office Commun, MIT License.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
<key>NSCameraUsageDescription</key><string>Websites can ask to use your camera. Search Mod Preview asks you first.</string>
<key>NSMicrophoneUsageDescription</key><string>Websites can ask to use your microphone. Search Mod Preview asks you first.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Save files you choose to download.</string>
</dict></plist>
PLIST
cp Search.sdef "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/Search-LICENSE.txt"
cp CREDITS.md "$APP/Contents/Resources/CREDITS.md"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
