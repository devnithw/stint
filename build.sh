#!/bin/sh
# Builds build/Stint.app for macOS 11+ as a universal binary (Apple silicon + Intel).
# Requires the Xcode Command Line Tools: xcode-select --install
#
#   sh build.sh              build build/Stint.app
#   sh build.sh snap [dir]   test build: render every view to PNGs in dir (default: build/snaps)
set -e
cd "$(dirname "$0")"
OUT=build
APP=$OUT/Stint.app
SRC="src/main.mm src/actions.mm src/format.mm src/gfx.mm src/icons.mm src/prefs.mm src/session.mm src/tray.mm
     src/trend.mm src/view_main.mm src/view_setup.mm src/views.mm src/widgets.mm src/window.mm"
FONTS="resources/fonts/StintInterTime.ttf resources/fonts/StintInterSemi.ttf resources/fonts/StintInterBody.ttf"
FLAGS="-std=c++17 -fobjc-arc -O2 -Wall -mmacosx-version-min=11.0"

if [ "$1" = snap ]; then
  DIR=${2:-$OUT/snaps}
  mkdir -p "$DIR" "$OUT/fonts"
  cp $FONTS "$OUT/fonts/"  # an unbundled binary loads ./fonts next to itself
  clang++ $FLAGS -DSTINT_SNAPSHOT $SRC -o "$OUT/stint_snap" -framework Cocoa -framework CoreText
  "$OUT/stint_snap" "$DIR"
  exit
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fonts"

clang++ $FLAGS -arch arm64 -arch x86_64 $SRC -o "$APP/Contents/MacOS/Stint" -framework Cocoa -framework CoreText
strip -x "$APP/Contents/MacOS/Stint"

clang -fobjc-arc -O2 -mmacosx-version-min=11.0 tools/makeicon.m -o "$TMP/makeicon" -framework Cocoa
"$TMP/makeicon" "$TMP/Stint.iconset"
iconutil -c icns "$TMP/Stint.iconset" -o "$APP/Contents/Resources/Stint.icns"

cp resources/Info.plist "$APP/Contents/Info.plist"
cp $FONTS resources/fonts/Inter-LICENSE.txt "$APP/Contents/Resources/fonts/"

# ad-hoc signature: required to run on Apple silicon; not a Developer ID signature
codesign --force --sign - "$APP"
ls -ld "$APP"
