#!/bin/sh
set -eu
. '/Volumes/T7 Shield/rea/spotmouse/scripts/build-env.sh'
mkdir -p "$YELPOINT_ROOT/assets" "$YELPOINT_BUILD/icons/YelPoint.iconset"
xcrun swiftc -module-cache-path "$YELPOINT_BUILD/swift" "$YELPOINT_ROOT/scripts/make-icons.swift" -o "$YELPOINT_BUILD/make-icons"
"$YELPOINT_BUILD/make-icons" "$YELPOINT_BUILD/icons"
for SIZE in 16 32 128 256 512; do
 cp "$YELPOINT_BUILD/icons/icon-$SIZE.png" "$YELPOINT_BUILD/icons/YelPoint.iconset/icon_${SIZE}x${SIZE}.png"
 DOUBLE=$((SIZE*2))
 cp "$YELPOINT_BUILD/icons/icon-$DOUBLE.png" "$YELPOINT_BUILD/icons/YelPoint.iconset/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$YELPOINT_BUILD/icons/YelPoint.iconset" -o "$YELPOINT_ROOT/assets/YelPoint.icns"
export YELPOINT_ROOT YELPOINT_BUILD
/usr/bin/python3 -B - <<'PY'
import os,struct
from pathlib import Path
root=Path(os.environ['YELPOINT_BUILD'])/'icons'
sizes=[16,32,48,64,128,256]
data=[(root/f'icon-{s}.png').read_bytes() for s in sizes]
offset=6+16*len(sizes)
headers=[]
for size,blob in zip(sizes,data):
 headers.append(struct.pack('<BBBBHHII',size%256,size%256,0,0,1,32,len(blob),offset));offset+=len(blob)
(Path(os.environ['YELPOINT_ROOT'])/'assets'/'YelPoint.ico').write_bytes(struct.pack('<HHH',0,1,len(sizes))+b''.join(headers)+b''.join(data))
PY
