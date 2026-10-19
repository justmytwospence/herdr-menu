#!/bin/sh
# Builds HerdrMenu.app next to this script.
set -e
cd "$(dirname "$0")"
app=HerdrMenu.app/Contents
mkdir -p "$app/MacOS" "$app/Resources"
swiftc HerdrMenu.swift -o "$app/MacOS/HerdrMenu"
cp sheep.png "$app/Resources/"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.pierre-charles.herdr-menu</string>
  <key>CFBundleName</key><string>HerdrMenu</string>
  <key>CFBundleExecutable</key><string>HerdrMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
