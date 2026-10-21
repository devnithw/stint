#!/bin/sh
# Builds Stint.app for macOS 11+ as a universal binary (Apple silicon + Intel).
# Requires the Xcode Command Line Tools: xcode-select --install
set -e
cd "$(dirname "$0")"
APP=Stint.app
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fonts"

clang++ -std=c++17 -fobjc-arc -O2 -Wall -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
  stint.mm -o "$APP/Contents/MacOS/Stint" -framework Cocoa -framework CoreText
strip -x "$APP/Contents/MacOS/Stint"

clang -fobjc-arc -O2 -mmacosx-version-min=11.0 mac/makeicon.m -o "$TMP/makeicon" -framework Cocoa
"$TMP/makeicon" "$TMP/Stint.iconset"
iconutil -c icns "$TMP/Stint.iconset" -o "$APP/Contents/Resources/Stint.icns"

cp mac/Info.plist "$APP/Contents/Info.plist"
cp fonts/StintInterTime.ttf fonts/StintInterSemi.ttf fonts/StintInterBody.ttf fonts/Inter-LICENSE.txt \
  "$APP/Contents/Resources/fonts/"

# ad-hoc signature: required to run on Apple silicon; not a Developer ID signature
codesign --force --sign - "$APP"
ls -ld "$APP"
