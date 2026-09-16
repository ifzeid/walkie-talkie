#!/usr/bin/env python3
"""Prepare and verify a signed Sparkle release locally; never uploads private keys."""
import argparse
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import html
import os
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
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
    # Detect architecture from this archive, not from an unrelated local app.
    binary_name = candidates[0].removesuffix('Info.plist') + 'MacOS/' + info['CFBundleExecutable']
    with tempfile.TemporaryDirectory(prefix='walkie-release-arch-') as temporary:
        binary = Path(temporary) / 'WalkieTalkie'
        binary.write_bytes(bundle.read(binary_name))
        architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
version = info['CFBundleShortVersionString']
if not version or not all(ch.isdigit() or ch == '.' for ch in version):
    raise SystemExit('Expected a numeric release version')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
destination = output / f'Walkie-Talkie-{version}.zip'
if destination.exists() and destination.read_bytes() != archive.read_bytes():
    raise SystemExit('An archive with this version already exists. Increase both version numbers before publishing again.')
shutil.copy2(archive, destination)
# Use a single official signing tool for all releases. Avoid requiring separate
# Keychain authorization for generate_keys, generate_appcast and sign_update.
tool = root / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
try:
    signature = subprocess.check_output([str(tool), '--account', 'app.walkietalkie.translator.updates',
                                         '-p', str(destination)], text=True, timeout=120).strip()
except subprocess.TimeoutExpired:
    raise SystemExit('Signing is waiting for macOS Keychain authorization. Authorize sign_update in the system dialog, then retry.')
if len(base64.b64decode(signature, validate=True)) != 64:
    raise SystemExit('Signing tool returned an invalid Ed25519 signature')
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = '对讲机 · Walkie Talkie'
ET.SubElement(channel, 'link').text = info.get('SUFeedURL', args.download_prefix)
ET.SubElement(channel, 'description').text = '对讲机版本更新'
ET.SubElement(channel, 'language').text = 'zh-CN'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'对讲机 {version}'
ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc), usegmt=True)
ET.SubElement(item, f'{{{ns}}}version').text = info['CFBundleVersion']
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
if architectures == ['arm64']:
    ET.SubElement(item, f'{{{ns}}}hardwareRequirements').text = 'arm64'
if args.notes:
    content = html.escape(args.notes.read_text())
    ET.SubElement(item, 'description').text = f'<div style="white-space:pre-wrap;font:13px -apple-system">{content}</div>'
ET.SubElement(item, 'enclosure', {
    'url': args.download_prefix.rstrip('/') + '/' + destination.name,
    'type': 'application/octet-stream',
    'length': str(destination.stat().st_size),
    f'{{{ns}}}edSignature': signature,
})
ET.indent(rss)
# Never leave an unverified appcast as the publishable file.
with tempfile.TemporaryDirectory(prefix='walkie-release-verify-') as temporary:
    candidate = Path(temporary) / 'appcast.xml'
    ET.ElementTree(rss).write(candidate, encoding='utf-8', xml_declaration=True)
    info_path = Path(temporary) / 'Info.plist'
    info_path.write_bytes(plistlib.dumps(info))
    env = os.environ.copy()
    env.setdefault('DEVELOPER_DIR', '/Library/Developer/CommandLineTools')
    subprocess.run(['swift', str(root / 'Scripts/VerifyUpdate.swift'), str(info_path), str(candidate), str(destination)],
                   env=env, check=True)
    shutil.copy2(candidate, output / 'appcast.xml')
print(f'Verified release: {destination.name} and appcast.xml in {output}')
