#!/bin/bash
# Voice Pipes from a terminal: the app, the `vp` command and the agent skill, with no prompts (agents can run it).
#
#   curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
#   curl -fsSL …/install.sh | bash -s -- --no-launch          # options go after `bash -s --`
#
# Options:
#   --apps-dir <dir>   where the app goes (default: where it already is, else /Applications, else ~/Applications)
#   --bin-dir <dir>    where `vp` is linked (default: /usr/local/bin if writable, else ~/.local/bin)
#   --version <x.y.z>  a specific release (default: the latest)
#   --no-skill         don't install the agent skill (Claude Code, Codex, ~/.agents)
#   --no-launch        don't start the app afterwards (it asks for Microphone and Accessibility on first launch)
#   --uninstall        remove the app, the vp links and the skill; your config and history stay
#
# The download is checked before anything is replaced: signed by Developer ID 7F3RGY9LG8, notarized by Apple.
# Exit codes: 0 ok, 1 failed, 2 bad usage.
set -euo pipefail

REPO="brancusi/voice-tools-releases"
TEAM="7F3RGY9LG8"
APP="Voice Pipes.app"

dest="" apps_dir="" bin_dir="" version="" skill=1 launch=1 uninstall=0

usage() {
  cat <<'USAGE'
Voice Pipes installer: the app, the vp command and the agent skill.
  curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash -s -- [options]
options:
  --apps-dir <dir>   where the app goes (default: where it is now, else /Applications, else ~/Applications)
  --bin-dir <dir>    where vp is linked (default: /usr/local/bin if writable, else ~/.local/bin)
  --version <x.y.z>  a specific release (default: latest)
  --no-skill         skip the agent skill
  --no-launch        don't start the app afterwards
  --uninstall        remove the app, vp links and skill (config and history stay)
USAGE
}

fail() { printf 'error: %s\n' "$1"; [[ -n "${2:-}" ]] && printf 'hint: %s\n' "$2"; exit "${3:-1}"; }
say() { printf '%s\n' "$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apps-dir) [[ $# -ge 2 ]] || fail "--apps-dir needs a directory" "" 2; apps_dir="${2/#\~/$HOME}"; shift 2 ;;
    --bin-dir) [[ $# -ge 2 ]] || fail "--bin-dir needs a directory" "" 2; bin_dir="${2/#\~/$HOME}"; shift 2 ;;
    --version) [[ $# -ge 2 ]] || fail "--version needs a version, e.g. 1.6.2" "" 2; version="${2#v}"; shift 2 ;;
    --no-skill) skill=0; shift ;;
    --no-launch) launch=0; shift ;;
    --uninstall) uninstall=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option $1" "options: --apps-dir --bin-dir --version --no-skill --no-launch --uninstall" 2 ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "Voice Pipes is a Mac app."
[[ "$(uname -m)" == "arm64" ]] || fail "Voice Pipes needs an Apple silicon Mac (M1 or later)."
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 14 ]] || fail "Voice Pipes needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."

# Where it's installed now, if anywhere (only --apps-dir when given).
existing=""
if [[ -n "$apps_dir" ]]; then candidates=("$apps_dir"); else candidates=(/Applications "$HOME/Applications"); fi
for dir in "${candidates[@]}"; do
  [[ -d "$dir/$APP" ]] && { existing="$dir"; break; }
done

# Only the copy being replaced: another copy elsewhere (a test install, a second Mac user's) is left running.
running() { pgrep -f "^$dest/$APP/Contents/MacOS/" >/dev/null 2>&1; }
quit_app() {
  running || return 0
  osascript -e "tell application \"$dest/$APP\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do running || return 0; sleep 0.5; done
  fail "Voice Pipes didn't quit." "quit it from the menu bar, then run this again"
}

if [[ $uninstall == 1 ]]; then
  [[ -n "$existing" ]] || fail "Voice Pipes isn't installed in ${apps_dir:-/Applications or ~/Applications}." "--apps-dir <dir> if it's elsewhere"
  dest="$existing"
  dest_real="$(cd "$dest" && pwd -P)"  # links may name it through /tmp → /private/tmp and the like
  exe="$existing/$APP/Contents/MacOS/VoiceTools"
  quit_app
  "$exe" --cli agents uninstall >/dev/null 2>&1 || true
  for link in /usr/local/bin/vp /usr/local/bin/voicepipes /opt/homebrew/bin/vp /opt/homebrew/bin/voicepipes \
              "$HOME/.local/bin/vp" "$HOME/.local/bin/voicepipes" ${bin_dir:+"$bin_dir/vp" "$bin_dir/voicepipes"}; do
    # Only links into the copy being removed; another program called vp, or another copy's link, is left alone.
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    target_dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || continue
    [[ "$target_dir/" == "$dest_real/$APP/"* ]] || continue
    if rm -f "$link" 2>/dev/null; then say "removed: $link"; else say "left: $link (root-owned: sudo rm $link)"; fi
  done
  rm -rf "${existing:?}/$APP"
  say "removed: $existing/$APP"
  say "kept: ~/.config/voice-pipes (config, vocabulary), ~/Library/Application Support/VoiceTools (history), Keychain keys"
  exit 0
fi

dest="${apps_dir:-${existing:-}}"
if [[ -z "$dest" ]]; then
  if [[ -w /Applications ]]; then dest="/Applications"; else dest="$HOME/Applications"; fi
fi
mkdir -p "$dest" 2>/dev/null || true
[[ -w "$dest" ]] || fail "can't write to $dest." "--apps-dir ~/Applications"

work="$(mktemp -d "${TMPDIR:-/tmp}/voicepipes.XXXXXX")"
mount="$work/mnt"
cleanup() { hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT

if [[ -n "$version" ]]; then
  url="https://github.com/$REPO/releases/download/v$version/Voice-Pipes-$version.dmg"
else
  url="https://github.com/$REPO/releases/latest/download/Voice-Pipes.dmg"
fi
say "downloading: $url"
curl -fsSL --retry 3 -o "$work/Voice-Pipes.dmg" "$url" || fail "download failed: $url" "check the version at https://github.com/$REPO/releases"

mkdir -p "$mount"
hdiutil attach "$work/Voice-Pipes.dmg" -nobrowse -readonly -noautoopen -mountpoint "$mount" -quiet \
  || fail "couldn't open the disk image."
src="$mount/$APP"
[[ -d "$src" ]] || fail "the disk image has no $APP."

# Never install something that isn't ours: Developer ID $TEAM, notarized, intact.
codesign --verify --deep --strict "$src" 2>/dev/null || fail "the app's signature doesn't verify; not installed."
signer="$(codesign -dv "$src" 2>&1 || true)"  # captured first: grep -q closing a pipe early would trip pipefail
[[ "$signer" == *"TeamIdentifier=$TEAM"* ]] || fail "the app isn't signed by Voice Pipes' developer ($TEAM); not installed."
spctl -a -t exec "$src" 2>/dev/null || fail "Gatekeeper rejects the app (not notarized?); not installed."
new_version="$(defaults read "$src/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"

was_running=0
running && was_running=1
quit_app
# Copy beside the old one, then swap, so a failed copy never leaves you without the app.
rm -rf "$dest/.$APP.new"
ditto "$src" "$dest/.$APP.new"
rm -rf "${dest:?}/$APP"
mv "$dest/.$APP.new" "$dest/$APP"
say "installed: $dest/$APP ($new_version)"

exe="$dest/$APP/Contents/MacOS/VoiceTools"
"$exe" --cli install ${bin_dir:+--dir "$bin_dir"}
if [[ $skill == 1 ]]; then "$exe" --cli agents install; fi

if [[ $launch == 1 || $was_running == 1 ]]; then
  open -g -a "$dest/$APP"
  say "started: Voice Pipes (menu bar). First launch asks for Microphone and Accessibility."
fi
say "next: vp   (status and tracks)"
