import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import zipfile

root=Path(os.environ['YELPOINT_ROOT'])
out=root/'dist'
app=out/'macOS'/'YelPoint.app'
win=out/'windows'
required=[app/'Contents'/'Info.plist',app/'Contents'/'MacOS'/'YelPoint',app/'Contents'/'_CodeSignature'/'CodeResources',win/'YelPoint.exe',win/'YelPoint-Setup.exe',win/'YelPoint.exe.config']
for file in required:
    if not file.is_file(): raise SystemExit('Missing build output: '+str(file))
with (app/'Contents'/'Info.plist').open('rb') as file:
    info=plistlib.load(file)
if info['CFBundleShortVersionString']!='1.0.0': raise SystemExit('Unexpected macOS app version')

def verify_pe(path):
    data=path.read_bytes()
    if data[:2]!=b'MZ': raise SystemExit('Missing PE header: '+str(path))
    pe=struct.unpack_from('<I',data,0x3c)[0]
    if data[pe:pe+4]!=b'PE\0\0' or struct.unpack_from('<H',data,pe+4)[0]!=0x8664:
        raise SystemExit('Windows build is not x64 PE: '+str(path))
    if struct.unpack_from('<H',data,pe+24+68)[0]!=2: raise SystemExit('Windows output has wrong subsystem')
for name in ['YelPoint.exe','YelPoint-Setup.exe']: verify_pe(win/name)
setup=(win/'YelPoint-Setup.exe').read_bytes()
for file,resource in [('YelPoint.exe',b'payload.exe\0'),('YelPoint.exe.config',b'payload.config\0')]:
    if resource not in setup or (win/file).read_bytes() not in setup:
        raise SystemExit('Installer payload is stale or incomplete: '+file)

readme=root/'사용법.txt'
(out/'macOS'/'사용법.txt').write_text(readme.read_text(),encoding='utf-8')
(win/'사용법.txt').write_text(readme.read_text(),encoding='utf-8-sig')
license_text=(root/'LICENSE.txt').read_text(encoding='utf-8')
(out/'macOS'/'LICENSE.txt').write_text(license_text,encoding='utf-8')
(win/'LICENSE.txt').write_text(license_text,encoding='utf-8-sig')
if not (win/'YelPoint-Setup.exe.config').exists():
    (win/'YelPoint-Setup.exe.config').write_bytes((win/'YelPoint.exe.config').read_bytes())

def app_files():
    for file in sorted(app.rglob('*')):
        if file.is_file() and not any(p.startswith('._') or p=='.DS_Store' for p in file.relative_to(app).parts): yield file

def add(archive,file,name):
    item=zipfile.ZipInfo(name)
    item.create_system=3
    mode=0o755 if '/Contents/MacOS/' in name or '/Contents/Helpers/' in name else 0o644
    item.external_attr=(0o100000|mode)<<16
    item.compress_type=zipfile.ZIP_DEFLATED
    archive.writestr(item,file.read_bytes())

scrcpy_files=['scrcpy.exe','scrcpy-server','adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','SDL3.dll','avcodec-63.dll','avformat-63.dll','avutil-61.dll','swresample-7.dll','libusb-1.0.dll','LICENSE.txt']
for name in scrcpy_files:
    if not (win/'scrcpy'/name).is_file(): raise SystemExit('Missing scrcpy file: '+name)
    if ('scrcpy/'+name).encode()+b'\0' not in setup: raise SystemExit('Installer is missing scrcpy/'+name)
for app_file in ['Contents/Helpers/scrcpy','Contents/Helpers/adb','Contents/Resources/scrcpy-server','Contents/Resources/THIRD-PARTY-NOTICES.txt']:
    if not (app/app_file).is_file(): raise SystemExit('Missing in the Mac app: '+app_file)
win_names=['YelPoint-Setup.exe','YelPoint-Setup.exe.config','YelPoint.exe','YelPoint.exe.config','사용법.txt','THIRD-PARTY-NOTICES.txt','LICENSE.txt']+['scrcpy/'+f for f in scrcpy_files]
mac_zip=out/'YelPoint-macOS.zip'
with zipfile.ZipFile(mac_zip,'w') as archive:
    for file in app_files():add(archive,file,'YelPoint.app/'+file.relative_to(app).as_posix())
    add(archive,out/'macOS'/'사용법.txt','사용법.txt')
    add(archive,root/'THIRD-PARTY-NOTICES.txt','THIRD-PARTY-NOTICES.txt')
    add(archive,out/'macOS'/'LICENSE.txt','LICENSE.txt')
win_zip=out/'YelPoint-Windows.zip'
with zipfile.ZipFile(win_zip,'w') as archive:
    for name in win_names:add(archive,win/name,name)
bundle=out/'YelPoint-1.0.0.zip'
with zipfile.ZipFile(bundle,'w') as archive:
    add(archive,readme,'사용법.txt')
    add(archive,out/'macOS'/'LICENSE.txt','LICENSE.txt')
    for file in app_files():add(archive,file,'macOS/YelPoint.app/'+file.relative_to(app).as_posix())
    for name in win_names:add(archive,win/name,'Windows/'+name)

files=[bundle,mac_zip,win_zip,win/'YelPoint-Setup.exe',win/'YelPoint.exe']
manifest={}
for file in files:
    digest=hashlib.sha256(file.read_bytes()).hexdigest()
    manifest[file.relative_to(out).as_posix()]={'bytes':file.stat().st_size,'sha256':digest}
    print(file.name, file.stat().st_size, digest)
(out/'SHA256SUMS.txt').write_text(''.join(f"{value['sha256']}  {name}\n" for name,value in manifest.items()))
(out/'build-info.json').write_text(json.dumps({'version':'1.0.0','macOS':{'minimum':'14.0','architectures':['arm64','x86_64']},'Windows':{'minimum':'Windows 10 with .NET Framework 4.8','architecture':'x64'},'files':manifest},ensure_ascii=False,indent=2))
for file in [bundle,mac_zip,win_zip]:
    with zipfile.ZipFile(file) as archive:
        bad=archive.testzip()
        if bad: raise SystemExit('Archive CRC failure: '+bad)
        if any('/data/' in n or '/._' in n or '/browser-' in n for n in archive.namelist()): raise SystemExit('Unexpected working data in archive')
print('PASS: PE headers, package CRCs, executable permissions and excluded working data')
