# Gotchas

Things that cost time, with the symptom, the cause and what the code does about it.

## macOS

**Permissions lost on every update.** Ad hoc signatures pin TCC grants (Accessibility, Microphone) to one
build's hash; an update looks like a new app. The old entry even stays switched on in System Settings while not
applying, and macOS won't prompt again while it exists. → Releases are signed with a fixed self-signed
certificate ([releasing](releasing.md)). Stale entries are cleared by **Fix…** with
`tccutil reset <service> io.github.brancusi.voice-tools`, which works without admin for the app's own bundle id
(it fails with `-10814` for an unregistered bundle id).

**Signing with a self-signed certificate.** `codesign` reports "no identity found" for a certificate that's only
in a keychain passed with `--keychain`; the keychain must be in the user search list
(`security list-keychains -d user -s <kc> …`). The certificate being untrusted (`CSSMERR_TP_NOT_TRUSTED`) doesn't
stop signing, and the designated requirement becomes `certificate root = H"…"`. Use LibreSSL's `/usr/bin/openssl`
for the `.p12` (OpenSSL 3's default encryption isn't readable by `security import`).

**Paste silently did nothing.** Two causes: (1) without Accessibility, `CGEvent` keystrokes are dropped with no
error; (2) events from a `combinedSessionState` source pick up physically held keys, so a ⌥ still down from the
⌥ Space trigger turned ⌘V into ⌥⌘V. → Check `AXIsProcessTrusted()` first and say so; wait for modifiers to be
released; post from a `.privateState` source; find the key code for `v`/`c` in the current layout (not 9/8,
which are QWERTY positions).

**The window "closed" when clicking away.** A menu-bar-only (`LSUIElement`) app has no Dock icon and isn't in
⌘Tab, so its window becomes unreachable behind other apps. → Switch activation policy to `.regular` while the main
window is open, back to `.accessory` on close; set `hidesOnDeactivate = false`.

**SwiftUI `Form` mislabels text fields.** In a grouped `Form` on macOS, `TextField("Claude Code", …)` renders the
title as a label beside the field and right-aligns the content — every row showed "Claude Code". → Outside forms,
use `TextField("", text:, prompt:)` + `.labelsHidden()`.

**Global hotkeys.** Carbon `RegisterEventHotKey` gives press *and* release (needed for hold-to-talk) without any
permission, but can't register modifier-only keys. Registering Esc globally would steal it from every app, so it's
registered only while recording. While recording a new shortcut in the editor, all hotkeys are suspended so the
old binding doesn't fire.

**Apple Foundation Models** reports `appleIntelligenceNotEnabled` until Apple Intelligence is switched on, then
`modelNotReady` while the model downloads.

**Off-screen rendering for checks.** `ImageRenderer` doesn't draw materials (blur); `NSView.cacheDisplay` draws
AppKit controls but drops SwiftUI text. Good enough to check layout, not looks.

## FluidAudio / on-device models

- `AsrManager.transcribe` needs an explicit `TdtDecoderState`
  (`TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)`); the README's stateless example doesn't
  match the current API.
- Parakeet is deterministic: the same audio always gives the same text. Training variety has to come from the
  audio (augmentation, other voices), not repeated calls.
- `SlidingWindowAsrManager` can reuse already-loaded `AsrModels` — loading is just assignment.
- FluidAudio's resource bundle (`FluidAudio_FluidAudio.bundle`) is only used by LuxTTS lexicons, and SwiftPM's
  generated `Bundle.module` looks next to the executable's bundle root, where a signed app can't put it. Don't
  call anything that needs it.
- Kokoro: ~510 phonemes per call (`phonemeSequenceTooLong`), and FluidAudio warns of an intermittent Apple BNNS
  crash on macOS 26.5 (fixed in 26.6). A crash would take the whole app down — run it in a helper process if
  shipped before 26.6.
- Supertonic voice styles aren't downloaded with the model; fetch `voice_styles/<V>.json` from
  `FluidInference/supertonic-3-coreml` and cache them.
- Models are cached per user in `~/Library/Application Support/FluidAudio/Models/`, shared between the app and any
  benchmark harness.

## OpenRouter

- `/api/v1/models` **omits speech and transcription models** unless you ask with `?output_modalities=speech` or
  `?output_modalities=transcription`. The catalog fetches all three and merges them.
- Speech models list their voices in `supported_voices`; some (Fish Audio, Seed) list none and take free-form ids.
- `/audio/speech` returns raw audio (`mp3` or `pcm`, default `pcm`); errors are JSON. `speed` is only honoured by
  some providers — others ignore it or return 400 — so speed is applied at playback.
- Transcription accepts multipart uploads (`file`, `model`) as well as base64 JSON.
- Live endpoint latency/throughput stats (`latency_last_30m`) are null without an API key.
- The `releases/latest/download/…` redirect can serve the previous release for a few seconds after publishing.

## Jev (TypeSafe)

- Endpoint `POST https://api.typesafe.ai/v1/systemone`. Without a key it returns **403** (the docs say 401) —
  handle both. 429/529 mean back off and retry.
- Batch: many independent questions about one `state` in a single request; `instructions` can be an object
  holding data plus the question, referring to fields in backticks. Each question repeats its own criteria, so
  tokens scale with question count (~280 per vocabulary question).
- `noul` is the probability of **yes**, not a boolean.
- `Tools/jev.sh` reads the key from the Keychain (`security` asks once to allow access) and never prints it.

## Build environment

- Only the Command Line Tools: SwiftPM builds and signs the app fine, but there's **no XCTest** — test with
  throwaway harnesses (see [Architecture → Testing](architecture.md#testing-approach)).
- MLX Swift (for a local LLM) needs its Metal shaders compiled, which SwiftPM can't do without Xcode; CI runners
  have Xcode, or llama.cpp (which embeds its Metal library) is the alternative.
- `swift build` caches aggressively; a "Build complete" in ~2 s after edits is normal.
