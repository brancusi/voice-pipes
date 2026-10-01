# Voice Tools

A macOS menu bar app that runs **tracks**: hotkey-triggered pipelines of building blocks.
Audio or text goes in, passes through steps (local or cloud transcription, LLM, HTTP, templates),
and comes out as pasted text, clipboard, speech, or a POST somewhere.

Default tracks:

| Track | Trigger | Pipeline |
|---|---|---|
| Fast dictation | ⌥ Space (hold) | Mic → Parakeet v3 (on-device, chunked on pauses) → Paste |
| Clean dictation | ⌥ ⇧ Space (toggle) | Mic → MAI-Transcribe-2 (OpenRouter) → Claude Haiku cleanup → Paste |
| Read aloud | ⌥ R (toggle: start / pause / resume) | Selection → page → clipboard → Speak |

## Build and run

Requires macOS 14+ and Swift 6 (Command Line Tools are enough; Xcode is not required).

```sh
Scripts/bundle.sh            # release build → build/Voice Tools.app
open "build/Voice Tools.app"
```

On first launch the app asks for **Microphone** and **Accessibility** (needed to paste and to read
selected text). Parakeet v3 (~460 MB) downloads once from Hugging Face and is cached.

Add your OpenRouter key under **Edit tracks… → Connections**. It's stored in the Keychain.

### Keeping permissions across rebuilds

Ad-hoc signed builds look like a new app to macOS on every rebuild, so Accessibility must be
re-granted. Create a self-signed code-signing certificate in Keychain Access
(Certificate Assistant → Create a Certificate → type *Code Signing*) and build with:

```sh
SIGN_IDENTITY="Voice Tools Dev" Scripts/bundle.sh
```

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
| Services | `Services/OpenRouterClient.swift`, `HTTPStep.swift`, `Keychain.swift` |
| System I/O | `IO/Clipboard.swift`, `TextCapture.swift`, `Speaker.swift` |
| UI | `UI/MenuView.swift`, `TrackEditorView.swift`, `HUD.swift` |
