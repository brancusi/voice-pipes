# Building and releasing

The pipeline mirrors Media Utilities (`another project`): tag → GitHub Actions build → signed zip + Sparkle
feed published to a public releases repo → installed copies update themselves.

## Local builds

```sh
DEV=1 ./build.sh                                   # build/Voice Tools.app — rebuilds over itself
SIGN_IDENTITY="Voice Tools Signing" DEV=1 ./build.sh   # same, signed like releases (shares their permissions)
./build.sh                                         # dist/Voice-Tools-<VERSION>-arm64.zip (+ .sha256); never overwrites
```

`build.sh`:

1. Fetches the pinned Sparkle release (SHA-256 checked) into `.cache/` for `bin/sign_update`; Sparkle itself comes
   in through SwiftPM at the same version (`build.sh` fails if they differ).
2. Draws the icon (`Tools/make_icon.swift` → `.icns`, no `iconutil`).
3. `swift build -c release --arch arm64`, then assembles the `.app`: binary, `Sparkle.framework` in
   `Contents/Frameworks` (rpath `@executable_path/../Frameworks`), generated `Info.plist` (including the Sparkle feed
   and public key when `UPDATE_PUBLIC_KEY` is present, and `NSMicrophoneUsageDescription`).
4. Signs with `SIGN_IDENTITY` (ad hoc if unset) and, for a real identity, fails unless the designated requirement
   names the certificate. `REQUIRE_SIGNING=1` / `REQUIRE_UPDATES=1` turn a missing identity / key into errors (CI
   sets both for tags).
5. Zips with `ditto` and writes the SHA-256.

FluidAudio's resource bundle is deliberately not copied: only its TTS lexicons use it and SwiftPM's accessor
wouldn't find it inside an app bundle anyway (see [Gotchas](gotchas.md)).

## Cutting a release

1. Add a `**x.y.z**` section at the top of `RELEASE_NOTES.md` (it becomes the release notes and the update
   dialog's text; only paragraphs, `- ` lists, `**bold**` and `` `code` `` are rendered).
2. Set `VERSION` to `x.y.z` (versions must increase — Sparkle compares them).
3. Commit, push, then:

   ```sh
   git tag -a vx.y.z -m "Voice Tools x.y.z" && git push origin vx.y.z
   ```

The workflow (`.github/workflows/release.yml`, `macos-15` runner) checks the tag matches `VERSION`, imports the
signing certificate into a temporary keychain, builds, signs the zip with the update key (refusing if the key
doesn't match `UPDATE_PUBLIC_KEY`), writes `appcast.xml` (`Tools/appcast.py`) and creates the release
`vx.y.z` in `brancusi/voice-tools-releases`. A manual run (`workflow_dispatch` with a version like `0.0.0-ci`)
builds and uploads an artifact without publishing — useful to check CI changes.

Verify a release from outside:

```sh
curl -fsSL "https://github.com/brancusi/voice-tools-releases/releases/latest/download/appcast.xml?t=$(date +%s)" | grep sparkle:version
```

The `latest` redirect can lag a few seconds after publishing.

## Signing and permissions

macOS ties Microphone and Accessibility grants to an app's **designated requirement**. Ad hoc signatures pin it to
one build's hash, so every update would lose permissions. Releases are signed with **Voice Tools Signing**, a
self-signed code-signing certificate, giving the requirement
`identifier "io.github.brancusi.voice-tools" and certificate root = H"e865aa…"`, which every release satisfies.
(0.3.0 was the one-time switch from ad hoc; users re-granted once.)

Sparkle accepts an update whose code signature changed as long as its EdDSA signature is valid (verified in
Sparkle 2.10's `SUUpdateValidator`), so a certificate change doesn't break updates — it only costs users one
permission re-grant.

## Secrets and keys

| What | Where | Used for |
|---|---|---|
| `SPARKLE_ED_PRIVATE_KEY` | Actions secret + your password manager | Signing update zips. Public half: `UPDATE_PUBLIC_KEY` (built into the app). Made once with `Tools/make_update_key.swift`. **If lost**, make a new pair and everyone reinstalls by hand once. |
| `SIGNING_CERT_P12` (base64) + `SIGNING_CERT_PASSWORD` | Actions secrets + your password manager | Code signing. Keep using the same certificate. |
| `RELEASES_TOKEN` | Actions secret | Fine-grained PAT, Contents read/write on `brancusi/voice-tools-releases` only. Releases stop publishing when it expires. |
| OpenRouter key | Keychain `io.github.brancusi.voice-tools` / `openrouter` (set in the app) | Cloud transcription, LLM, speech. |
| TypeSafe Jev key | Keychain `io.github.brancusi.voice-tools` / `typesafe` (set in the app) | Vocabulary training judgments; `Tools/jev.sh`. |

GitHub never shows a secret back, so the password-manager copies are the only way to restore one.

## Troubleshooting

- **Permissions requested again after an update** — the build wasn't signed with the certificate. Check
  `codesign -d -r- "/Applications/Voice Tools.app"` names `certificate root`. To compare with what macOS stored:
  `sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select hex(csreq) from access where client='io.github.brancusi.voice-tools'"`, then `csreq -r <file> -t`.
- **A stale permission blocks the prompt** — Setup → Checks → **Fix…** (runs `tccutil reset` for this app only).
- **CI fails at "Sign the update"** — `SPARKLE_ED_PRIVATE_KEY` doesn't match `UPDATE_PUBLIC_KEY`.
- **CI fails at "Publish release"** — `RELEASES_TOKEN` missing, expired, or lacks the releases repo.
