#!/bin/sh
set -eu
. '/Volumes/T7 Shield/rea/spotmouse/scripts/build-env.sh'
# Third-party files must match their official releases (vendor/VENDOR-SHA256.txt).
(cd "$YELPOINT_ROOT/vendor" && grep -v '^#' VENDOR-SHA256.txt | shasum -a 256 -c --quiet) || { echo 'Bundled third-party files do not match vendor/VENDOR-SHA256.txt' >&2; exit 1; }
export YELPOINT_BUILD
/usr/bin/python3 -B "$YELPOINT_ROOT/scripts/bootstrap-windows-build.py"
TOOLS="$YELPOINT_BUILD/windows-tools"
REF="$TOOLS/net48/build/.NETFramework/v4.8"
CSC="$TOOLS/compiler/tasks/netcore/bincore/csc.dll"
OUT="$YELPOINT_ROOT/dist/windows"
mkdir -p "$OUT"
export DOTNET_ROOT="$TOOLS/dotnet" DOTNET_ROLL_FORWARD=Major
"$TOOLS/dotnet/dotnet" "$CSC" -nologo -noconfig -nostdlib+ -utf8output -deterministic+ -optimize+ -target:winexe -platform:x64 \
  -r:"$REF/mscorlib.dll" -r:"$REF/System.dll" -r:"$REF/System.Core.dll" \
  -r:"$REF/System.Drawing.dll" -r:"$REF/System.Windows.Forms.dll" \
  -r:"$REF/System.Runtime.Serialization.dll" -r:"$REF/System.Xml.dll" \
  -win32manifest:"$YELPOINT_ROOT/windows/app.manifest" -win32icon:"$YELPOINT_ROOT/assets/YelPoint.ico" \
  -resource:"$YELPOINT_ROOT/assets/YelPoint.ico",YelPoint.ico \
  -resource:"$YELPOINT_ROOT/assets/guide-windows-ko.mp4",guide-ko.mp4 \
  -resource:"$YELPOINT_ROOT/assets/guide-windows-en.mp4",guide-en.mp4 \
  -resource:"$YELPOINT_ROOT/assets/guide.html",guide.html \
  -resource:"$YELPOINT_ROOT/assets/pop.wav",pop.wav \
  -resource:"$YELPOINT_ROOT/vendor/fonts/NanumPenScript-Regular.ttf",NanumPenScript-Regular.ttf \
  -resource:"$YELPOINT_ROOT/vendor/fonts/NanumGothic-Bold.ttf",NanumGothic-Bold.ttf \
  -resource:"$YELPOINT_ROOT/vendor/fonts/NanumMyeongjo-Bold.ttf",NanumMyeongjo-Bold.ttf \
  -out:"$OUT/YelPoint.exe" \
  "$YELPOINT_ROOT/windows/Native.cs" "$YELPOINT_ROOT/windows/Model.cs" \
  "$YELPOINT_ROOT/windows/Overlays.cs" "$YELPOINT_ROOT/windows/Toolbar.cs" \
  "$YELPOINT_ROOT/windows/Controller.cs" "$YELPOINT_ROOT/windows/Recorder.cs" "$YELPOINT_ROOT/windows/Phone.cs" "$YELPOINT_ROOT/windows/Qr.cs" "$YELPOINT_ROOT/windows/Board.cs" "$YELPOINT_ROOT/windows/Subtitles.cs" "$YELPOINT_ROOT/windows/Program.cs"
cp "$YELPOINT_ROOT/windows/YelPoint.exe.config" "$OUT/YelPoint.exe.config"
# Android phone screen and document camera: scrcpy 5.0.1 (Apache 2.0) beside the program.
SCRCPY="$YELPOINT_ROOT/vendor/scrcpy-5.0.1/win64"
SCRCPY_FILES="scrcpy.exe scrcpy-server adb.exe AdbWinApi.dll AdbWinUsbApi.dll SDL3.dll avcodec-63.dll avformat-63.dll avutil-61.dll swresample-7.dll libusb-1.0.dll LICENSE.txt"
# The installer's resource list is built from a staging path without spaces.
STAGE="$YELPOINT_BUILD/scrcpy-win"
rm -rf "$OUT/scrcpy" "$STAGE"; mkdir -p "$OUT/scrcpy" "$STAGE"
SCRCPY_RES=""
for f in $SCRCPY_FILES; do cp "$SCRCPY/$f" "$OUT/scrcpy/$f"; cp "$SCRCPY/$f" "$STAGE/$f"; SCRCPY_RES="$SCRCPY_RES -resource:$STAGE/$f,scrcpy/$f"; done
cp "$YELPOINT_ROOT/THIRD-PARTY-NOTICES.txt" "$OUT/THIRD-PARTY-NOTICES.txt"
if [ -f "$YELPOINT_ROOT/windows/Installer.cs" ]; then
"$TOOLS/dotnet/dotnet" "$CSC" -nologo -noconfig -nostdlib+ -utf8output -deterministic+ -optimize+ -target:winexe -platform:x64 \
  -r:"$REF/mscorlib.dll" -r:"$REF/System.dll" -r:"$REF/System.Core.dll" \
  -r:"$REF/System.Drawing.dll" -r:"$REF/System.Windows.Forms.dll" \
  -win32manifest:"$YELPOINT_ROOT/windows/app.manifest" -win32icon:"$YELPOINT_ROOT/assets/YelPoint.ico" \
  -resource:"$OUT/YelPoint.exe",payload.exe -resource:"$OUT/YelPoint.exe.config",payload.config \
  -resource:"$YELPOINT_ROOT/THIRD-PARTY-NOTICES.txt",notices.txt $SCRCPY_RES \
  -resource:"$YELPOINT_ROOT/assets/YelPoint.ico",YelPoint.ico \
  -out:"$OUT/YelPoint-Setup.exe" "$YELPOINT_ROOT/windows/Installer.cs"
cp "$YELPOINT_ROOT/windows/YelPoint.exe.config" "$OUT/YelPoint-Setup.exe.config"
fi
echo "Built Windows executable: $OUT/YelPoint.exe"
