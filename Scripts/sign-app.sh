#!/bin/bash
set -euo pipefail
APP="$1"
SIGNER="${WALKIE_SIGN_IDENTITY:--}"
if [[ "$SIGNER" != "-" ]]; then
  # Use the SAME Apple signing identity on every release for Keychain continuity.
  FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for item in "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc" "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app"; do
    codesign --force --options runtime --timestamp --sign "$SIGNER" "$item"
  done
  codesign --force --options runtime --timestamp --sign "$SIGNER" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGNER" "$APP"
else
  # Preserve Sparkle's vendor signatures; sign only our outer app for local use.
  codesign --force --sign - "$APP"
fi
