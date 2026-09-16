#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p .build
swiftc -parse-as-library -swift-version 5 Sources/WalkieTalkie/Models.swift Sources/WalkieTalkie/AppStore.swift Sources/WalkieTalkie/CredentialCache.swift Sources/WalkieTalkie/UpdateConfiguration.swift Sources/WalkieTalkie/SelectionTranslationService.swift Scripts/SmokeTests.swift -o .build/SmokeTests
.build/SmokeTests
