#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Spotlight Plus.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/build/module-cache"
cp Sources/SpotlightPlus.swift build/main.swift
xcrun swiftc build/main.swift -o "$APP/Contents/MacOS/SpotlightPlus" -framework AppKit -framework SwiftUI -framework ApplicationServices -module-cache-path "$PWD/build/module-cache" -target "$(uname -m)-apple-macosx14.0" -O
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/SpotlightPlusIcon-v2.icns"
codesign --force --sign - --identifier de.nils.spotlightplus "$APP"
# Notify file metadata consumers that an existing app bundle has been updated.
touch "$APP"
"$APP/Contents/MacOS/SpotlightPlus" --self-test
printf 'Built: %s\n' "$APP"
