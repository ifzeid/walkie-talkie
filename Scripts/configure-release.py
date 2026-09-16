#!/usr/bin/env python3
"""Apply public release configuration; never reads API keys or signing private keys."""
import os
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlparse

path = Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
feed = os.environ.get("WALKIE_UPDATE_FEED", "").strip()
if feed:
    url = urlparse(feed)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise SystemExit("WALKIE_UPDATE_FEED must be a public HTTPS appcast URL without credentials or query parameters")
    data["SUFeedURL"] = feed
path.write_bytes(plistlib.dumps(data, sort_keys=False))
