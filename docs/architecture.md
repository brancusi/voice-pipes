# Architecture

A single SwiftUI menu bar app (`LSUIElement`) built with SwiftPM, no Xcode project. Two dependencies:
[FluidAudio](https://github.com/FluidInference/FluidAudio) (on-device Parakeet ASR and TTS models on the Neural
Engine) and [Sparkle](https://sparkle-project.org) (self-updates).

## Code map

| Area | Files | Responsibility |
|---|---|---|
| App | `App/VoiceToolsApp.swift` | Scenes: `MenuBarExtra` (panel) and the `Window("Voice Pipes")`. Menu bar icon reflects the run state / an update. |
| Model | `Model/Track.swift` | `Track`, `Trigger`, `Step`, `StepKind` (every block, with input/output `DataKind`, titles, catalog, defaults), `ParakeetMode`, `LocalVoiceEngine`. |
| | `Model/TrackStore.swift` | Loads/saves `tracks.json`; one-time migrations; trigger conflict detection. |
| | `Model/HistoryStore.swift` | `RunRecord` and `history.json`: the last 1,000 runs (text, heard, failure, timings), written off the main thread. |
| | `Model/Vocabulary.swift` | `VocabularyEntry`, `VocabularyStore` (`vocabulary.json`), `FixWords` (the replacement algorithm). |
| | `Model/KeyCombo.swift` | Hotkeys as Carbon key codes + modifiers; layout-aware key names; key code for a character. |
| Engine | `Pipeline/AppState.swift` | The runtime: hotkey registration, trigger semantics, mic capture, step execution, checks. |
| Hotkeys | `Hotkeys/HotkeyManager.swift` | Carbon `RegisterEventHotKey` (press *and* release events, no Accessibility needed). |
| Audio | `Audio/AudioRecorder.swift` | `AVAudioEngine` input tap → 16 kHz mono Float32; `cut()` for back-to-back takes; WAV encoder. |
| | `Audio/ParakeetService.swift` | Parakeet v3 load/transcribe; `LiveTranscriber` protocol with `ChunkedTranscriber` and `StreamingTranscriber`. |
| | `Audio/PauseChunker.swift` | Splits live audio at pauses (pure logic). |
| | `Audio/LocalVoices.swift` | Pocket TTS and Supertonic-3: lazy load, streaming synthesis, Supertonic voice downloads. |
| | `Audio/VocabularyTrainer.swift` | Audio augmentation + transcription to collect mishearings. |
| Services | `Services/OpenRouterClient.swift` | Transcription (multipart), chat completions, speech (MP3), key validation, connection pre-warm. |
| | `Services/OpenRouterCatalog.swift` | OpenRouter model list (3 merged queries), daily disk cache, prices, voice labels. |
| | `Services/JevClient.swift` | TypeSafe Jev: batched yes/no judgments and Route choices, with backoff. |
| | `Services/HTTPStep.swift` | The HTTP block and `Template`. |
| | `Services/Keychain.swift` | Generic-password items under `io.github.brancusi.voice-tools`. |
| System I/O | `IO/Clipboard.swift` | Clipboard history, paste (⌘V) and selection copy (⌘C) via synthetic keystrokes. |
| | `IO/TextCapture.swift` | Selected text and page text via the Accessibility API. |
| | `IO/Speaker.swift` | Read-aloud playback for all three engine families, with pause/resume/progress. |
| UI | `UI/Theme.swift` | The design system in code: `Palette` (Sundown / Daylight, follows the system appearance; the HUD stays dark), `VPFont` (SF Mono scale), button styles, `Keycap`, `SectionLabel`, `vpCard()`, `vpWindow()`, pipeline category colours. Source of truth: the Voice Pipes design system artifact. |
| | `UI/Components.swift` | Shared design-system pieces: cards, check codes, `VPSegmented`, `VPTextField`, checkboxes, filter chips, the wordmark, `PixelHeadline` (bundled Silkscreen), track palette colours. |
| | `UI/Wrangler.swift`, `UI/WranglerArt.swift` | The mascot drawn crisp at whole-pixel scales; the art is a generated 20 × 30 grid per pose, converted exactly from the design system's SVGs. |
| | `UI/AboutView.swift` | The About window: the pixel sundown scene with the Wrangler, version, hotkeys, release notes, updates. |
| | `UI/MenuView.swift` | The panel (launcher). |
| | `UI/MainWindow.swift` | Main window: Tracks / History / Vocabulary / Setup; activation-policy switching. |
| | `UI/TrackEditorView.swift` | Track editor, step rows, per-block configuration, key recorder. |
| | `UI/ModelPicker.swift` | Unified model picker (on-device + OpenRouter) and OpenRouter voice picker. |
| | `UI/TrainWordSheet.swift` | Vocabulary training flow. |
| | `UI/HUD.swift` | The floating status tag (`NSPanel`, click-through). |
| Updates | `Updates/Updates.swift` | Sparkle controller + 5-minute feed poll + notifications. |
| | `Updates/Diagnostics.swift` | The Checks list, one-click permission fixes, the copyable report. |
| | `UI/MenuBarGlyph.swift` | The menu bar icon: the Wrangler as an 18 × 18 template image (idle, update, three lasso frames while recording). |
| | `UI/SetupView.swift` | Setup: checks, connections and keys, on-device models, Appearance (Auto / Daylight / Sundown), updates. |
| Tools | `Tools/` | Icon renderer (`make_icon.swift` paints the 32-px pixel mark into every iconset size), update-key generator, appcast writer, `jev.sh` (Jev from the shell). |

## How a track runs

```
hotkey press/release ──► AppState.handleTrigger
        │  capture in progress for this track? → toggle press / hold release ends it
        │  this track is speaking? → pause / resume (or cancel while still loading)
        ▼
AppState.start(track)
        │  first step Microphone? → beginCapture       otherwise → runSteps(from: 0, payload: .none)
        ▼
beginCapture: AudioRecorder.start(); Esc registered as cancel; OpenRouter pre-warmed if any step uses it;
              if step 2 is Parakeet in chunk/stream mode, a LiveTranscriber is fed audio while you talk
        ▼  (release / second press)
finishCapture: stop mic; ignore < 0.25 s; live transcriber → finish (falls back to whole-clip if it fails/empty)
        ▼
runSteps: for each step, execute(kind, payload) → payload   (Payload = .none | .audio([Float]) | .text(String))
          per-step timings → HUD + History; a failing step stops the run (LLM can pass its input through) and its
          text so far still goes to History
```

Steps are typed by `StepKind.input` / `.output` (`DataKind`), and `Track.validationError` rejects a mismatched
chain before it runs. Output steps (paste, copy, HUD) return their input so tracks can keep going.

## Speech-to-text

- **Parakeet** (`ParakeetService`): FluidAudio `AsrManager` with Parakeet TDT 0.6B v3, loaded at launch if any track
  uses it. Each call gets a fresh `TdtDecoderState`; clips under 1 s are zero-padded.
- **Modes** (`ParakeetMode`, stored optional so pre-0.2 tracks decode as *On release*):
  - *On release* — transcribe the whole recording; 40–140 ms for 4–33 s of speech on an M5 Max.
  - *Chunk at pauses* — `PauseChunker` cuts at pauses (threshold from 10th/90th-percentile frame levels over the
    last 3 s; chunks ≥ 3 s, ≤ 14 s); `ChunkedTranscriber` transcribes chunks in order while recording.
  - *Streaming* — FluidAudio `SlidingWindowAsrManager` (11 s windows, 2 s context) on the already-loaded models.
- **OpenRouter** (`OpenRouterClient.transcribe`): WAV upload, multipart, on release.

[Research](research.md) has the measurements that made *On release* the default.

## Text-to-speech

`Speaker` plays three engine families with one control surface (state, progress, pause/resume, clear):

| Engine | How it plays |
|---|---|
| macOS voices | `AVSpeechSynthesizer`; progress from word callbacks. |
| OpenRouter | Text split into passages (first ≤ 240 chars for a fast start, then ≤ 1,200); each fetched as MP3 while the previous one plays (`AVAudioPlayer`, rate for speed). |
| On-device (Pocket TTS, Supertonic-3) | Generated audio is scheduled on an `AVAudioPlayerNode` → `AVAudioUnitTimePitch` (speed) as it arrives; Pocket streams 80 ms frames, Supertonic returns a passage at a time. The run waits for the last buffer to play. |

Speed is applied at playback for every engine, because only some providers honour a `speed` parameter.

## Vocabulary

- `FixWords.apply` builds one case-insensitive regex alternation of every Heard-as phrase (and each spelling
  itself), longest first, with Unicode letter/number lookarounds for whole-word matching and `\s+` between words.
  Matches are mapped back to their entry and replaced with the spelling; an all-lowercase spelling is capitalised
  after a sentence end unless *always exact*.
- `VocabularyTrainer`: Parakeet is deterministic, so variety comes from the audio — 30 variants per take
  (speed by resampling, gain, seeded noise, lead-in silence), plus optional Pocket/Supertonic renditions resampled
  to 16 kHz. Results are normalised (lowercase, punctuation stripped), counted, and compared with the spelling.
- `JevClient.judgeReplacements` sends each candidate as a Jev *noul* (yes/no) question, 25 per request, requests
  in parallel; `≥ 0.6` is pre-ticked.

## Routing

A `route(routes:)` step sends the text to Jev as one `choice` question: each route's name is an option and its
*Use when…* text that option's criteria. The chosen route's model and prompt then run through the same call as an
LLM step (glossary included). The step's title in the live run is replaced with the pick and Jev's time, so the HUD
and History show it. If Jev fails (no key, network), the first route runs.

## Persistence and migrations

`TrackStore` decodes `tracks.json`; enums with associated values use Swift's synthesized `Codable`
(`{"parakeet": {"chunkOnPauseMs": 500, "mode": "onRelease"}}`). New associated values are added as **optionals**
so old files still decode. If decoding fails, the file is moved aside, never overwritten.

One-time migrations run at load, each guarded by a `UserDefaults` flag:

| Flag | Version | Change |
|---|---|---|
| `migration.readAloudPocket.v1` | 0.5.1 | "Read aloud" Speak step → Pocket TTS (speed kept) |
| `migration.fixWords.v1` | 0.6.0 | Insert Fix words after the first transcription step |

## Windows, focus and permissions

- The app is `LSUIElement` (no Dock icon). While the main window is open it switches to `.regular` so it's in the
  Dock and ⌘Tab, and back to `.accessory` when it closes; the window never hides on deactivate.
- The HUD is a borderless, non-activating `NSPanel` at `.statusBar` level that ignores the mouse; it fades out.
- Paste and selection capture post synthetic ⌘V/⌘C from a **private** event source after the trigger's modifiers
  are released, using the key code that types `v`/`c` in the current layout. They require Accessibility; without
  it, paste throws a visible error and leaves the text on the clipboard.
- Global hotkeys use Carbon and need no permission. Esc is registered only while recording.

See [Gotchas](gotchas.md) for why each of these is the way it is.

## Checks

`Diagnostics.run` produces the Checks list on demand (panel open, Setup, key changes, model state changes):
microphone and Accessibility status, Parakeet and on-device voice state, OpenRouter key validity (`/api/v1/key`),
hotkeys taken by other apps, duplicate hotkeys, track validation errors, tracks without triggers. A permission
**Fix** runs `tccutil reset <service> io.github.brancusi.voice-tools` (clearing stale entries from older builds),
re-requests, opens the Settings pane, then polls for the grant.

## Testing approach

There's no XCTest with the Command Line Tools alone, so logic is tested with throwaway harnesses: copy or compile
the relevant source files with a `main.swift` (e.g. `FixWords` cases, `PauseChunker` on synthetic audio,
`TrackStore` migrations on a *copy* of the real `tracks.json`), or a scratch SwiftPM package that depends on the
local FluidAudio checkout for model benchmarks. Views can be checked by rendering an `NSHostingView` off-screen.

## Look

The UI follows the Voice Pipes design system; [brand](brand.md) maps its tokens, icons and mascot to the files
that implement them.
