#!/bin/sh
set -eu
. '/Volumes/T7 Shield/rea/spotmouse/scripts/build-env.sh'
# Third-party files must match their official releases (vendor/VENDOR-SHA256.txt).
(cd "$YELPOINT_ROOT/vendor" && grep -v '^#' VENDOR-SHA256.txt | shasum -a 256 -c --quiet) || { echo 'Bundled third-party files do not match vendor/VENDOR-SHA256.txt' >&2; exit 1; }
APP="$YELPOINT_BUILD/macOS/YelPoint.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK=$(xcrun --show-sdk-path)
for ARCH in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macosx14.0" -sdk "$SDK" \
      -module-cache-path "$YELPOINT_BUILD/swift" \
      -framework AppKit -framework AVKit -framework ScreenCaptureKit -framework CoreImage -framework Carbon \
      "$YELPOINT_ROOT"/macos/*.swift -o "$YELPOINT_BUILD/YelPoint-$ARCH"
done
xcrun lipo -create "$YELPOINT_BUILD/YelPoint-arm64" "$YELPOINT_BUILD/YelPoint-x86_64" -output "$APP/Contents/MacOS/YelPoint"
/usr/bin/python3 -B "$YELPOINT_ROOT/scripts/write-plist.py" "$APP/Contents/Info.plist"
if [ -f "$YELPOINT_ROOT/assets/YelPoint.icns" ]; then cp "$YELPOINT_ROOT/assets/YelPoint.icns" "$APP/Contents/Resources/YelPoint.icns"; fi
rm -f "$APP/Contents/Resources/guide.mp4"
cp "$YELPOINT_ROOT/assets/guide-mac-ko.mp4" "$APP/Contents/Resources/guide-ko.mp4"
cp "$YELPOINT_ROOT/assets/guide-mac-en.mp4" "$APP/Contents/Resources/guide-en.mp4"
cp "$YELPOINT_ROOT/assets/pop.wav" "$APP/Contents/Resources/pop.wav"
# Android phone screen and document camera: scrcpy 5.0.1 (Apache 2.0) with its adb.
SCRCPY="$YELPOINT_ROOT/vendor/scrcpy-5.0.1/mac"
mkdir -p "$APP/Contents/Helpers"
cp "$SCRCPY/scrcpy" "$SCRCPY/adb" "$APP/Contents/Helpers/"
chmod 755 "$APP/Contents/Helpers/scrcpy" "$APP/Contents/Helpers/adb"
cp "$SCRCPY/scrcpy-server" "$APP/Contents/Resources/scrcpy-server"
cp "$SCRCPY/LICENSE" "$APP/Contents/Resources/scrcpy-LICENSE.txt"
cp "$YELPOINT_ROOT/THIRD-PARTY-NOTICES.txt" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"
# Chalkboard handwriting: Nanum Pen Script, SIL Open Font License 1.1.
cp "$YELPOINT_ROOT/vendor/fonts/NanumPenScript-Regular.ttf" "$YELPOINT_ROOT/vendor/fonts/NanumPenScript-OFL.txt" "$APP/Contents/Resources/"
# Burned-in subtitles: Nanum Gothic Bold, SIL Open Font License 1.1.
cp "$YELPOINT_ROOT/vendor/fonts/NanumGothic-Bold.ttf" "$YELPOINT_ROOT/vendor/fonts/NanumGothic-OFL.txt" "$APP/Contents/Resources/"
# Board sans and serif lettering: Nanum Gothic Bold (above) and Nanum Myeongjo Bold, SIL Open Font License 1.1.
cp "$YELPOINT_ROOT/vendor/fonts/NanumMyeongjo-Bold.ttf" "$YELPOINT_ROOT/vendor/fonts/NanumMyeongjo-OFL.txt" "$APP/Contents/Resources/"
xattr -cr "$APP/Contents/Helpers"
codesign --force --sign - "$APP/Contents/Helpers/scrcpy" "$APP/Contents/Helpers/adb"
# Ad-hoc signatures default to a per-build hash, which voids privacy permissions on every
# rebuild. Pinning the requirement to the identifier keeps them across builds.
codesign --force --sign - --identifier studio.yelpoint.app -r='designated => identifier "studio.yelpoint.app"' "$APP"
"$APP/Contents/MacOS/YelPoint" --self-test
DEST="$YELPOINT_ROOT/dist/macOS/YelPoint.app"
export APP DEST
/usr/bin/python3 -B - <<'PY'
import os,shutil
from pathlib import Path
destination=Path(os.environ['DEST'])
def remove_error(function,path,error):
    if not isinstance(error[1],FileNotFoundError): raise error[1]
if destination.exists(): shutil.rmtree(destination,onerror=remove_error)
shutil.copytree(os.environ['APP'],destination,copy_function=shutil.copyfile,ignore=shutil.ignore_patterns('._*','.DS_Store'))
PY
codesign --verify "$DEST"
echo "Built: $DEST"
