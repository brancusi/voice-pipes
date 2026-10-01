#!/usr/bin/env bash
# Builds VoiceTools and wraps it in build/Voice Tools.app.
#
# Usage: Scripts/bundle.sh [debug|release]   (default: release)
#
# Signing: set SIGN_IDENTITY to a codesigning identity name to keep macOS permissions
# (Accessibility, Microphone) across rebuilds. Ad-hoc signing ("-") works, but macOS treats
# each rebuild as a new app and asks for Accessibility again.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Voice Tools.app"
IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/VoiceTools" "$APP/Contents/MacOS/VoiceTools"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftPM resource bundles from dependencies, if any.
find "$BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --deep --sign "$IDENTITY" --identifier local.VoiceTools "$APP"
echo "Built $APP (signed with: $IDENTITY)"
