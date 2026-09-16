#!/usr/bin/env python3
"""Test real signed executables against one disposable Keychain item; no user API keys are read."""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
env = dict(os.environ, DEVELOPER_DIR='/Library/Developer/CommandLineTools')
folder = Path(tempfile.mkdtemp(prefix='walkie-keychain-regression-', dir='/private/tmp'))
creator = folder / 'CreatorA'
reader = folder / 'ReaderB'
metadata = folder / 'fixture.json'
source_files = [
    'Sources/WalkieTalkie/Models.swift', 'Sources/WalkieTalkie/AppStore.swift',
    'Sources/WalkieTalkie/CredentialCache.swift', 'Scripts/CredentialIntegration.swift'
]
subprocess.run(['swiftc', '-parse-as-library', '-swift-version', '5', *source_files, '-o', str(creator)], cwd=root, env=env, check=True)
shutil.copy2(creator, reader)
for executable, suffix in [(creator, 'creator'), (reader, 'reader')]:
    subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', 'app.walkietalkie.regression.' + suffix, str(executable)], check=True)
def run(binary, mode):
    subprocess.run([str(binary), mode, str(metadata)], env=env, check=True, timeout=20)
try:
    run(creator, 'create')
    run(creator, 'restart')
    run(reader, 'changed-signature')
    run(creator, 'restart')
finally:
    if metadata.exists():
        run(creator, 'cleanup')
