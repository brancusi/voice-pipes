#!/usr/bin/env bash
# Call TypeSafe's Jev with the key Voice Pipes keeps in the Keychain (Setup → TypeSafe (Jev)).
# The key is read straight into the request header and never printed.
#
#   Tools/jev.sh request.json                          # POST a full request body (model defaults to jev-latest)
#   echo '{"state": "...", "questions": {...}}' | Tools/jev.sh -
#   Tools/jev.sh --judge "Aram Zadikian" "aram zedickian" "aaron's attacking"
#       # the Vocabulary trainer's question: is each candidate safe to always replace with the target?
#
# First use: macOS asks whether `security` may read the Voice Pipes item; choose Always Allow.
set -euo pipefail

SERVICE="io.github.brancusi.voice-tools"
ENDPOINT="https://api.typesafe.ai/v1/systemone"

key() {
  security find-generic-password -s "$SERVICE" -a typesafe -w 2>/dev/null \
    || { echo "No Jev key in the Keychain. Add it in Voice Pipes → Setup → TypeSafe (Jev)." >&2; exit 1; }
}

post() {
  local token
  token="$(key)" || exit 1
  # Header passed via curl's config on stdin so the key never appears in the process list.
  curl -sS --fail-with-body --max-time 30 "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -K - --data-binary "@$1" <<<"header = \"Authorization: Bearer $token\""
}

if [[ "${1:-}" == "--judge" ]]; then
  shift
  target="$1"; shift
  body="$(mktemp)"; trap 'rm -f "$body"' EXIT
  python3 - "$target" "$@" > "$body" <<'PY'
import json, sys
target, candidates = sys.argv[1], sys.argv[2:]
question = ("Speech recognition heard someone say `target` and wrote `candidate` instead. A replacement rule would "
            "rewrite every occurrence of `candidate` as `target` in everything this person dictates: emails, chat, "
            "notes and code. Should `candidate` be replaced?")
criteria = {
    "true": "`candidate` is a garbled transcription of `target`: not a real word or phrase, name, product, code identifier or term someone would intentionally write, so replacing it is safe.",
    "false": "`candidate` is (or contains as a whole) ordinary language, a different real name, or a term used in coding or another field, so replacing it could change text the person meant.",
}
print(json.dumps({
    "model": "jev-latest",
    "state": {"task": "Building a personal dictation vocabulary of automatic spelling corrections.", "target": target},
    "questions": {f"c{i}": {"type": "noul", "instructions": {"target": target, "candidate": c, "question": question},
                            "criteria": criteria} for i, c in enumerate(candidates)},
}))
PY
  response="$(post "$body")" || exit 1
  python3 - "$response" "$@" <<'PY'
import json, sys
answers = json.loads(sys.argv[1])["answers"]
for i, c in enumerate(sys.argv[2:]):
    p = answers[f"c{i}"]["noul"]
    print(f"{p*100:5.1f}%  {'replace' if p >= 0.6 else 'keep   '}  {c}")
PY
  exit 0
fi

src="${1:--}"
body="$(mktemp)"; trap 'rm -f "$body"' EXIT
if [[ "$src" == "-" ]]; then cat > "$body"; else cat "$src" > "$body"; fi
# Default the model if the body doesn't name one.
python3 -c 'import json,sys; b=json.load(open(sys.argv[1])); b.setdefault("model","jev-latest"); json.dump(b,open(sys.argv[1],"w"))' "$body"
post "$body"
echo
