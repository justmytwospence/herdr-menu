#!/bin/sh
# Builds HerdrMenu.app next to this script.
set -e
cd "$(dirname "$0")"
app=HerdrMenu.app/Contents
mkdir -p "$app/MacOS" "$app/Resources"
swiftc HerdrMenu.swift -o "$app/MacOS/HerdrMenu"
cp sheep.png "$app/Resources/"
# App icon from herdr's logo (logo.png, 512px): an iconset of every size up to 512, packed into AppIcon.icns
iconset=$(mktemp -d)/AppIcon.iconset
mkdir "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s logo.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
  [ $((s * 2)) -le 512 ] && sips -z $((s * 2)) $((s * 2)) logo.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Resources/AppIcon.icns"
rm -r "$(dirname "$iconset")"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.pierre-charles.herdr-menu</string>
  <key>CFBundleName</key><string>HerdrMenu</string>
  <key>CFBundleExecutable</key><string>HerdrMenu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
