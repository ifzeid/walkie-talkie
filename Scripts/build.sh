#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Library/Developer/CommandLineTools ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p .build
swift build -c release --scratch-path .build
swift Scripts/GenerateIcon.swift "$PWD"
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
STAGING_DIR="$(mktemp -d /private/tmp/walkie-talkie-release.XXXXXX)"
APP="$STAGING_DIR/对讲机.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"
BIN_DIR="$(swift build -c release --scratch-path .build --show-bin-path)"
cp "$BIN_DIR/WalkieTalkie" "$APP/Contents/MacOS/WalkieTalkie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
SPARKLE_DIR="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto --norsrc --noextattr "$SPARKLE_DIR" "$APP/Contents/Frameworks/Sparkle.framework"
# Optionally bake a fixed HTTPS update feed into production builds.
python3 Scripts/configure-release.py "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'CFBundleDisplayName = "Walkie Talkie";\nCFBundleName = "Walkie Talkie";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf 'CFBundleDisplayName = "对讲机";\nCFBundleName = "对讲机";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
printf '"用对讲机翻译" = "Translate with Walkie Talkie";\n' > "$APP/Contents/Resources/en.lproj/ServicesMenu.strings"
printf '"用对讲机翻译" = "用对讲机翻译";\n' > "$APP/Contents/Resources/zh-Hans.lproj/ServicesMenu.strings"
xattr -cr "$APP"
./Scripts/sign-app.sh "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
mkdir -p "$PWD/dist"
ditto --norsrc --noextattr "$APP" "$PWD/dist/对讲机.app"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$PWD/dist/Walkie-Talkie.zip"
echo "Built: $PWD/dist/对讲机.app"
echo "Verified archive: $PWD/dist/Walkie-Talkie.zip"
