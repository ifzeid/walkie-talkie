#!/usr/bin/env python3
"""Prepare signed Sparkle files locally; never uploads or publishes."""
import argparse
import plistlib
import shutil
import subprocess
import zipfile
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--download-prefix', required=True, help='Public HTTPS directory containing the versioned ZIP')
parser.add_argument('--output', type=Path, default=root / 'Releases')
parser.add_argument('--notes', type=Path, help='Release notes to embed in the update dialog')
args = parser.parse_args()
url = urlparse(args.download_prefix)
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
    parser.error('--download-prefix must be a public HTTPS URL without credentials or query parameters')
archive = root / 'dist/Walkie-Talkie.zip'
with zipfile.ZipFile(archive) as bundle:
    candidates = [name for name in bundle.namelist() if name.count('/') == 2 and name.endswith('.app/Contents/Info.plist')]
    if len(candidates) != 1:
        raise SystemExit('Expected exactly one top-level application in the archive')
    info = plistlib.loads(bundle.read(candidates[0]))
    if info.get('CFBundleIdentifier') != 'app.walkietalkie.translator':
        raise SystemExit('Archive belongs to a different application')
version = info['CFBundleShortVersionString']
if not all(ch.isdigit() or ch == '.' for ch in version):
    raise SystemExit('Expected a numeric release version')
tools = root / '.build/artifacts/sparkle/Sparkle/bin'
account = 'app.walkietalkie.translator.updates'
public_key = subprocess.check_output([str(tools / 'generate_keys'), '--account', account, '-p'], text=True, timeout=30).strip()
if public_key != info.get('SUPublicEDKey'):
    raise SystemExit('The app verification key does not match this Mac’s update signing key')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
destination = output / f'Walkie-Talkie-{version}.zip'
if destination.exists() and destination.read_bytes() != archive.read_bytes():
    raise SystemExit('An archive with this version already exists. Increase both app version and build number before publishing again.')
shutil.copy2(archive, destination)
if args.notes:
    shutil.copy2(args.notes, destination.with_suffix('.md'))
subprocess.run([str(tools / 'generate_appcast'), '--account', account,
                '--download-url-prefix', args.download_prefix.rstrip('/') + '/',
                '--embed-release-notes', '--maximum-deltas', '0', '--maximum-versions', '0', str(output)], check=True, timeout=120)
print(f'Ready to upload: {destination.name} and appcast.xml in {output}')
