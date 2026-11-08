#!/bin/sh
# Renders the usage videos in both languages. Run after a tool changes.
set -eu
. '/Volumes/T7 Shield/rea/spotmouse/scripts/build-env.sh'
BIN="$YELPOINT_BUILD/make-guide"
xcrun swiftc -O -module-cache-path "$YELPOINT_BUILD/swift" -framework AppKit -framework AVFoundation \
  "$YELPOINT_ROOT/scripts/make-guide.swift" -o "$BIN"
if [ "${1:-}" = "--sheet" ]; then
  shift
  "$BIN" --sheet "$@"
  exit 0
fi
"$BIN" "$YELPOINT_ROOT/assets/guide-mac-ko.mp4"
"$BIN" "$YELPOINT_ROOT/assets/guide-mac-en.mp4" --english
"$BIN" "$YELPOINT_ROOT/assets/guide-windows-ko.mp4" --windows
"$BIN" "$YELPOINT_ROOT/assets/guide-windows-en.mp4" --windows --english
