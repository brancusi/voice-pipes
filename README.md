# Voice Tools

A macOS menu bar app that runs **tracks**: hotkey-triggered pipelines of building blocks.
Audio or text goes in, passes through steps (local or cloud transcription, LLM, HTTP, templates),
and comes out as pasted text, clipboard, speech, or a POST somewhere.

Default tracks:

| Track | Trigger | Pipeline |
|---|---|---|
| Fast dictation | ⌥ Space (hold) | Mic → Parakeet v3 (on-device, chunked on pauses) → Paste |
| Clean dictation | ⌥ ⇧ Space (toggle) | Mic → MAI-Transcribe-2 (OpenRouter) → Claude Haiku cleanup → Paste |
| Read aloud | ⌥ R (toggle: start / pause / resume) | Selection → page → clipboard → Speak (OpenRouter MAI-Voice-2.1, or a macOS voice) |

## Install

1. Download `Voice-Tools-<version>-arm64.zip` from the [releases](https://github.com/brancusi/voice-tools-releases/releases) and unzip it.
2. Move **Voice Tools.app** to Applications.
3. The app isn't notarized yet, so the first time: **right-click → Open → Open**. After that it opens normally.
4. It lives in the menu bar (the mic icon). To start it at login: System Settings → General → Login Items → add Voice Tools.

On first launch it asks for **Microphone** and **Accessibility** (needed to paste and to read selected text);
the panel's **Checks** list shows what's missing, with a button to fix each. Parakeet v3 (~460 MB) downloads once
and is cached. Add your OpenRouter key in **Open Voice Tools… → Setup**; it's stored in the Keychain.

After that it keeps itself up to date.

## Build

```sh
./build.sh                 # → dist/Voice-Tools-<VERSION>-arm64.zip
DEV=1 ./build.sh           # → build/Voice Tools.app, for local iteration
open "build/Voice Tools.app"
```

Needs macOS 14+ and Swift 6 (Command Line Tools are enough). The icon is drawn in code (`Tools/make_icon.swift`).
Sparkle (the updater) comes in through SwiftPM, pinned to the same version as `SPARKLE_VERSION` in `build.sh`,
which also fetches that release's `sign_update` tool into `.cache/` (checked against its SHA-256).

### Code signing and permissions

macOS remembers Microphone and Accessibility permissions per app *identity*. An ad hoc signature changes with
every build, so each update would look like a new app and lose its permissions. Releases are therefore signed
with **Voice Tools Signing**, a self-signed code-signing certificate (no Apple developer account needed): the
app's identity becomes "`io.github.brancusi.voice-tools` signed by that certificate", which stays the same
across versions. `build.sh` fails if a signed build's requirement doesn't name the certificate.

The certificate (`.p12`) and its password live in the `SIGNING_CERT_P12` (base64) and `SIGNING_CERT_PASSWORD`
Actions secrets and in a password manager. Keep using the same one: a new certificate means everyone grants
permissions once more (updates still install, since Sparkle accepts a changed certificate when the EdDSA
signature is valid).

To sign local builds the same way (so a dev build shares the installed app's permissions), import the `.p12`
into your login keychain once (double-click it), then `SIGN_IDENTITY="Voice Tools Signing" DEV=1 ./build.sh`.
Without it, local builds are ad hoc.

## Releases and updates

Releases are built by GitHub Actions: update `RELEASE_NOTES.md`, bump `VERSION`, then push a tag `v<VERSION>`.
The workflow builds the app, signs the zip with the update key, writes the update feed (`appcast.xml`, via
`Tools/appcast.py`), and publishes all three to the public releases repo,
[brancusi/voice-tools-releases](https://github.com/brancusi/voice-tools-releases/releases). This repo stays
private; that one holds only the app.

Installed copies read `https://github.com/brancusi/voice-tools-releases/releases/latest/download/appcast.xml`
every 5 minutes and when the panel opens, and install only an update signed by the key whose public half is in
`UPDATE_PUBLIC_KEY` (built into the app). Versions must go up: Sparkle compares them.

The key pair is made once with `Tools/make_update_key.swift`. The private half lives in the
`SPARKLE_ED_PRIVATE_KEY` Actions secret and in a password manager, never in the repo. The workflow refuses to
publish if it doesn't match `UPDATE_PUBLIC_KEY`. If it's ever lost, make a new pair, and everyone installs the
next version by hand once. A build without `UPDATE_PUBLIC_KEY` has updates turned off.

## How it works

- **Tracks** live in `~/Library/Application Support/VoiceTools/tracks.json` and can be edited by hand.
- **Triggers**: any number per track. *Toggle* = press to start, press to stop. *Press & hold* = record
  while held. Pressing a speaking track's trigger pauses/resumes. Esc cancels a recording.
- **Steps** declare input/output types (`none`, `audio`, `text`); the editor flags mismatches.
- **Fast path**: when Parakeet directly follows Microphone, audio is split at pauses and each phrase is
  transcribed while you're still talking, so release only waits for the last phrase.
- **Cloud path**: audio uploads on release; the OpenRouter connection is pre-warmed when recording starts.

| Layer | Files |
|---|---|
| Model | `Model/Track.swift`, `KeyCombo.swift`, `TrackStore.swift` |
| Engine | `Pipeline/AppState.swift` (trigger handling, capture, step execution) |
| Audio | `Audio/AudioRecorder.swift`, `PauseChunker.swift`, `ParakeetService.swift` |
| Services | `Services/OpenRouterClient.swift`, `OpenRouterCatalog.swift` (model list for pickers), `HTTPStep.swift`, `Keychain.swift` |
| System I/O | `IO/Clipboard.swift`, `TextCapture.swift`, `Speaker.swift` |
| UI | `UI/MenuView.swift` (menu bar launcher), `MainWindow.swift` (Tracks, Activity, Setup), `TrackEditorView.swift`, `ModelPicker.swift`, `HUD.swift` |
| Updates & checks | `Updates/Updates.swift` (Sparkle), `Updates/Diagnostics.swift` |
