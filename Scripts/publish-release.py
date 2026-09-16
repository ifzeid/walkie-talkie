#!/usr/bin/env python3
"""Build, sign, verify and publish a GitHub Release from a clean source checkout.

Signing remains on this Mac. No private key is exported or sent to GitHub.
The draft is made public only after both the archive and appcast are uploaded.
"""
import argparse
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*command, capture=False):
    return subprocess.run(command, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='ifzeid/walkie-talkie')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
        parser.error('Expected OWNER/REPOSITORY')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    build = info['CFBundleVersion']
    if not re.fullmatch(r'\d+(?:\.\d+)*', version) or not build.isdigit():
        raise SystemExit('Expected a numeric version and build number')
    feed = f'https://github.com/{args.repo}/releases/latest/download/appcast.xml'
    if info.get('SUFeedURL') != feed:
        raise SystemExit('The bundled update feed must match this GitHub repository')
    tag = f'v{version}'
    notes = ROOT / 'ReleaseNotes' / f'{version}.md'
    if not notes.is_file():
        raise SystemExit(f'Missing release notes: {notes}')
    if run('git', 'status', '--porcelain', capture=True).strip():
        raise SystemExit('Commit all source changes before publishing')
    remote = run('git', 'remote', 'get-url', 'origin', capture=True).strip()
    if remote not in (f'https://github.com/{args.repo}.git', f'git@github.com:{args.repo}.git', f'https://github.com/{args.repo}'):
        raise SystemExit('Git origin does not match --repo')
    releases = run('gh', 'release', 'list', '--repo', args.repo, '--json', 'tagName', '--jq', '.[].tagName', capture=True).splitlines()
    if tag in releases:
        raise SystemExit('This release already exists. Never replace a published version; increment both version numbers.')
    run('gh', 'repo', 'view', args.repo, '--json', 'url,visibility')
    run('./Scripts/build.sh')
    built = plistlib.loads((ROOT / 'dist/对讲机.app/Contents/Info.plist').read_bytes())
    for field in ('CFBundleShortVersionString', 'CFBundleVersion', 'SUPublicEDKey', 'SUFeedURL'):
        if built.get(field) != info.get(field):
            raise SystemExit(f'Build configuration differs from committed source: {field}')
    # Retries can rebuild a byte-different ZIP before any version is public.
    # Keep each attempt separate; never overwrite previously prepared files.
    releases_directory = ROOT / 'Releases'
    releases_directory.mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=f'{version}-', dir=releases_directory))
    run('python3', 'Scripts/prepare-release.py', '--output', str(output),
        '--notes', str(notes), '--download-prefix', f'https://github.com/{args.repo}/releases/download/{tag}/')
    archive = output / f'Walkie-Talkie-{version}.zip'
    appcast = output / 'appcast.xml'
    # prepare-release verifies this exact archive with the bundled public key
    # and rejects a tampered copy before writing appcast.xml.
    if run('git', 'status', '--porcelain', capture=True).strip():
        raise SystemExit('The build changed tracked files. Commit them and rebuild before publishing.')
    # Create the tag only after the final signed archive has passed verification.
    existing = subprocess.run(['git', 'rev-parse', '--verify', f'refs/tags/{tag}'], cwd=ROOT,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    head = run('git', 'rev-parse', 'HEAD', capture=True).strip()
    if existing.returncode == 0:
        tagged = run('git', 'rev-list', '-n', '1', tag, capture=True).strip()
        if tagged != head:
            raise SystemExit('The release tag points to a different commit')
    else:
        run('git', 'tag', '-a', tag, '-m', f'对讲机 {version}')
    branch = run('git', 'branch', '--show-current', capture=True).strip()
    if not branch:
        raise SystemExit('Publish from a branch, not a detached checkout')
    run('git', 'push', 'origin', branch, tag)
    run('gh', 'release', 'create', tag, '--repo', args.repo, '--verify-tag', '--draft',
        '--title', f'对讲机 {version}', '--notes-file', str(notes), str(archive), str(appcast))
    run('gh', 'release', 'edit', tag, '--repo', args.repo, '--draft=false', '--latest')
    print(f'Published: https://github.com/{args.repo}/releases/tag/{tag}')
    print(f'Update feed: {feed}')


if __name__ == '__main__':
    main()
