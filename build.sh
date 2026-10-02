#!/usr/bin/env bash
# Build "Voice Pipes.app" for Apple silicon (macOS 14+) and zip it into dist/.
#   ./build.sh                 # version from ./VERSION → dist/Voice-Pipes-<VERSION>-arm64.zip
#   VERSION=1.2.0 ./build.sh
#   DEV=1 ./build.sh           # local iteration: build/Voice Pipes.app only, no zip or DMG, can rebuild over itself
# Releases produce dist/Voice-Pipes-<VERSION>-arm64.zip (Sparkle updates) and dist/Voice-Pipes-<VERSION>.dmg (the
# installer people download; dmgbuild is pinned and installed into .cache/ on first use).
# Needs Xcode or the Command Line Tools (swift, codesign). Never overwrites an existing dist/ file.
#
# Self-updating (Sparkle): Sparkle comes in through SwiftPM (pinned in Package.swift). The release tarball of the
# same version is also fetched into .cache/ (checked against its SHA-256) for bin/sign_update, which CI uses to sign
# the zip. When UPDATE_PUBLIC_KEY (the file, or the env var) holds the update signing key's public half, the app
# checks FEED_URL (every 5 minutes itself; Sparkle hourly, its minimum). Without a key the app builds with updates
# off; REQUIRE_UPDATES=1 makes that an error.
#
# Signing: releases are signed with the "Developer ID Application: Aram Zadikian (7F3RGY9LG8)" certificate (from
# the SIGNING_CERT_P12 secret), so macOS keeps Microphone and Accessibility permissions, and Keychain access, across
# updates: it remembers the app by its identifier and team instead of by one build's hash. Developer ID builds get
# the hardened runtime (with the microphone entitlement) and, when NOTARY_KEY_PATH, NOTARY_KEY_ID and
# NOTARY_ISSUER_ID name an App Store Connect API key, are notarized and stapled; REQUIRE_NOTARIZATION=1 makes a
# missing key an error. Set SIGN_IDENTITY to sign local builds the same way. Without it the build is ad hoc, which
# macOS treats as a new app every time; REQUIRE_SIGNING=1 makes that an error.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(cat VERSION)}"
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
FEED_URL="${FEED_URL:-https://github.com/brancusi/voice-tools-releases/releases/latest/download/appcast.xml}"
UPDATE_PUBLIC_KEY="${UPDATE_PUBLIC_KEY:-$(cat UPDATE_PUBLIC_KEY 2>/dev/null || true)}"
if [[ -z "$UPDATE_PUBLIC_KEY" && "${REQUIRE_UPDATES:-0}" == 1 ]]; then
  echo "REQUIRE_UPDATES=1 but no UPDATE_PUBLIC_KEY; see Tools/make_update_key.swift." >&2; exit 1
fi
grep -q "Sparkle\", exact: \"$SPARKLE_VERSION\"" Package.swift \
  || { echo "Package.swift's Sparkle version doesn't match SPARKLE_VERSION ($SPARKLE_VERSION)." >&2; exit 1; }

NAME="Voice Pipes"
DIST="dist"
ZIP="$DIST/Voice-Pipes-$VERSION-arm64.zip"
if [[ "${DEV:-0}" != 1 && -e "$ZIP" ]]; then
  echo "$ZIP already exists; bump VERSION instead of rebuilding over it." >&2; exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/voice-tools.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "==> Sparkle $SPARKLE_VERSION tools"
SPARKLE=".cache/Sparkle-$SPARKLE_VERSION"
if [[ ! -x "$SPARKLE/bin/sign_update" ]]; then
  mkdir -p .cache
  curl -fsSL -o "$WORK/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $WORK/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null \
    || { echo "Sparkle download doesn't match its pinned SHA-256." >&2; exit 1; }
  mkdir -p "$WORK/sparkle" && tar -xf "$WORK/sparkle.tar.xz" -C "$WORK/sparkle"
  mkdir -p "$SPARKLE" && ditto "$WORK/sparkle/bin" "$SPARKLE/bin"
fi

echo "==> icon"
CACHE=(-module-cache-path "$WORK/module-cache")
swiftc -O "${CACHE[@]}" Tools/make_icon.swift -o "$WORK/make_icon"
"$WORK/make_icon" "$WORK/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns" >/dev/null
# Silkscreen, the pixel face for flavour headlines (empty states, training success), with its OFL licence.
ditto Resources/Fonts "$APP/Contents/Resources/Fonts"
# Model quality ratings for the pickers (curated per release; see Resources/model-ratings.json).
cp Resources/model-ratings.json "$APP/Contents/Resources/model-ratings.json"

echo "==> compile (arm64, macOS 14+)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"
cp "$BIN/VoiceTools" "$APP/Contents/MacOS/VoiceTools"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# FluidAudio's resource bundle (LuxTTS lexicons) isn't copied: the app only uses its ASR, which needs none.

UPDATE_KEYS=""
if [[ -n "$UPDATE_PUBLIC_KEY" ]]; then
  UPDATE_KEYS="  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$UPDATE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>3600</integer>"
  echo "    updates on: $FEED_URL"
else
  echo "    updates off (no UPDATE_PUBLIC_KEY)"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.brancusi.voice-tools</string>
  <key>CFBundleExecutable</key><string>VoiceTools</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Voice Pipes records your voice when you press a dictation hotkey.</string>
$UPDATE_KEYS
</dict></plist>
PLIST

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" && "${REQUIRE_SIGNING:-0}" == 1 ]]; then
  echo "REQUIRE_SIGNING=1 but no SIGN_IDENTITY; users would have to grant permissions again." >&2; exit 1
fi
echo "==> sign (${IDENTITY/#-/ad hoc})"
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
  # Inside out, each piece with the hardened runtime and a secure timestamp, as notarization requires.
  # (Self-signed and ad hoc builds can't use the runtime: library validation would refuse to load Sparkle.)
  ENTITLEMENTS="$WORK/VoiceTools.entitlements"
  cat > "$ENTITLEMENTS" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
ENT
  SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  # Sparkle's own order; the Downloader keeps its entitlements (network access for its sandbox).
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPK/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$IDENTITY" "$SPK/XPCServices/Downloader.xpc"
  for item in "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
  done
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
  # The designated requirement must name the team, or permissions won't carry over between versions.
  codesign -d -r- "$APP" 2>&1 | grep -q 'subject.OU' \
    || { echo "Signed app's requirement doesn't name the team:" >&2; codesign -d -r- "$APP" >&2; exit 1; }
else
  codesign --force --deep --sign "$IDENTITY" "$APP"
  if [[ "$IDENTITY" != "-" ]]; then
    # The designated requirement must name the certificate, or permissions won't carry over between versions.
    codesign -d -r- "$APP" 2>&1 | grep -q 'certificate root' \
      || { echo "Signed app's requirement doesn't name the certificate:" >&2; codesign -d -r- "$APP" >&2; exit 1; }
  fi
fi

if [[ -n "${NOTARY_KEY_PATH:-}" && "$IDENTITY" == "Developer ID Application"* ]]; then
  echo "==> notarize"
  ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
  xcrun notarytool submit "$WORK/notarize.zip" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait --timeout 30m | tee "$WORK/notary.log"
  grep -q "status: Accepted" "$WORK/notary.log" || { echo "Notarization failed." >&2; exit 1; }
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
elif [[ "${REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
  echo "REQUIRE_NOTARIZATION=1 but no Developer ID identity or NOTARY_KEY_PATH." >&2; exit 1
fi

if [[ "${DEV:-0}" == 1 ]]; then
  mkdir -p build && rm -rf "build/$NAME.app" && ditto "$APP" "build/$NAME.app"
  echo "built build/$NAME.app"
  exit 0
fi

echo "==> package"
mkdir -p "$DIST"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "built $ZIP"

# The installer people download: a DMG with the app, an Applications link and a pixel-sundown window telling them
# to drag one onto the other. (The zip above is what Sparkle installs updates from.)
echo "==> dmg"
DMG="$DIST/Voice-Pipes-$VERSION.dmg"
DMGBUILD_VERSION="1.6.5"
VENV=".cache/dmgbuild-$DMGBUILD_VERSION"
[[ -x "$VENV/bin/dmgbuild" ]] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q "dmgbuild==$DMGBUILD_VERSION"; }
swiftc "${CACHE[@]}" Tools/make_dmg_background.swift -o "$WORK/make_dmg_background"
"$WORK/make_dmg_background" "$WORK/dmg-bg" >/dev/null
tiffutil -cathidpicheck "$WORK/dmg-bg/background.png" "$WORK/dmg-bg/background@2x.png" -out "$WORK/dmg-bg/background.tiff" 2>/dev/null
# GitHub's macOS runners sometimes fail hdiutil with "Resource busy"; try a few times.
for attempt in 1 2 3; do
  "$VENV/bin/dmgbuild" -s Tools/dmg_settings.py -D app="$APP" -D background="$WORK/dmg-bg/background.tiff" "$NAME" "$DMG" >/dev/null && break
  [[ $attempt == 3 ]] && { echo "dmgbuild failed three times." >&2; exit 1; }
  echo "    dmgbuild failed (attempt $attempt); retrying" >&2; rm -f "$DMG"; sleep 10
done
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" --wait --timeout 30m | tee "$WORK/notary-dmg.log"
    grep -q "status: Accepted" "$WORK/notary-dmg.log" || { echo "DMG notarization failed." >&2; exit 1; }
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  fi
fi
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "built $DMG"
