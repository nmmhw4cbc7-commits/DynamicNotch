#!/bin/bash
set -e
cd "$(dirname "$0")"
NAME="DynamicNotch"
APP="build/$NAME.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" build/dmg

echo "▶ Kompiliere…"
swiftc -O -target arm64-apple-macos14.0  Sources/*.swift -o build/$NAME-arm64
swiftc -O -target x86_64-apple-macos14.0 Sources/*.swift -o build/$NAME-x86
lipo -create build/$NAME-arm64 build/$NAME-x86 -output "$APP/Contents/MacOS/$NAME"
rm build/$NAME-arm64 build/$NAME-x86

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>local.dynamicnotch</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSCalendarsUsageDescription</key><string>Zeigt deinen nächsten Termin in der Notch.</string>
<key>NSAppleEventsUsageDescription</key><string>Zeigt und steuert die Wiedergabe in Spotify und Musik.</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Zeigt deinen nächsten Termin in der Notch.</string>
</dict></plist>
PLIST

echo "▶ Kopiere Icon…"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶ Signiere (ad-hoc)…"
# Feste Signatur-Identität, damit macOS-Rechte (Bedienungshilfen, Festplattenzugriff) nach jedem Build erhalten bleiben
codesign --force --deep --sign - --identifier local.dynamicnotch \
  --requirements '=designated => identifier "local.dynamicnotch"' "$APP" \
  || codesign --force --deep --sign - "$APP"

echo "▶ Erstelle DMG…"
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "$NAME" -srcfolder build/dmg -ov -format UDZO "$NAME.dmg" >/dev/null

echo "✅ Fertig: $(pwd)/$NAME.dmg"
[ -z "$CI" ] && open . || true
