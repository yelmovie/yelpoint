"""Fetch a small, pinned C# toolchain onto the verified external APFS image."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import urllib.request
import zipfile

ROOT = Path(os.environ['YELPOINT_BUILD']) / 'windows-tools'
ROOT.mkdir(parents=True, exist_ok=True)

def get(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()

runtime = ROOT / 'dotnet'
if not (runtime / 'dotnet').exists():
    metadata = json.loads(get('https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json'))
    release = metadata['releases'][0]['runtime']
    item = next(f for f in release['files'] if f['rid'] == 'osx-arm64' and f['name'].endswith('.tar.gz'))
    print('Downloading .NET runtime', release['version'], flush=True)
    raw = get(item['url'])
    if hashlib.sha512(raw).hexdigest().lower() != item['hash'].lower():
        raise RuntimeError('Runtime checksum mismatch')
    archive = ROOT / 'runtime.tar.gz'
    archive.write_bytes(raw)
    runtime.mkdir(exist_ok=True)
    with tarfile.open(archive) as package:
        for member in package.getmembers():
            target = (runtime / member.name).resolve()
            if target != runtime.resolve() and not str(target).startswith(str(runtime.resolve()) + os.sep):
                raise RuntimeError('Unexpected runtime archive path')
        package.extractall(runtime)
    archive.unlink()

for name, version, folder in [
    ('microsoft.net.compilers.toolset', '4.8.0', 'compiler'),
    ('microsoft.netframework.referenceassemblies.net48', '1.0.3', 'net48'),
]:
    destination = ROOT / folder
    if (destination / '.complete').exists():
        continue
    print('Downloading', name, version, flush=True)
    base = f'https://api.nuget.org/v3-flatcontainer/{name}/{version}/{name}.{version}.nupkg'
    raw = get(base)
    # NuGet's registration metadata supplies the package hash in base64.
    metadata = json.loads(get(f'https://api.nuget.org/v3/registration5-semver1/{name}/{version}.json'))
    catalog = json.loads(get(metadata['catalogEntry']))
    expected = catalog.get('packageHash')
    if expected and hashlib.sha512(raw).digest() != base64.b64decode(expected):
        raise RuntimeError('Package checksum mismatch: ' + name)
    archive = ROOT / (folder + '.zip')
    archive.write_bytes(raw)
    destination.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            target = (destination / member.filename).resolve()
            if not str(target).startswith(str(destination.resolve()) + os.sep):
                raise RuntimeError('Unexpected NuGet archive path')
        package.extractall(destination)
    (destination / '.complete').write_text(version)
    archive.unlink()

os.chmod(runtime / 'dotnet', 0o755)
print('Windows compiler ready:', ROOT, flush=True)
