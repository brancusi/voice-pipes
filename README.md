# Voice Tools

A macOS menu bar app for voice: dictate into any app, have text read aloud, or ask questions — each as a
**track**, a hotkey-triggered pipeline of building blocks you assemble yourself.

```
⌥ Space (hold)      Mic → Parakeet v3 (on this Mac) → Fix words → Paste             ~50–150 ms after you let go
⌥ ⇧ Space (toggle)  Mic → MAI-Transcribe-2 → Fix words → Claude Haiku cleanup → Paste  (OpenRouter)
⌥ R (toggle)        Selection / page / clipboard → Speak (Pocket TTS, on this Mac)     pause/resume with ⌥ R
```

Every block is swappable: transcription on this Mac or any OpenRouter model, cleanup with any LLM, speech from
on-device models, macOS voices or any OpenRouter voice, plus HTTP requests, templates, paste, copy and more.

Apple silicon, macOS 14 or later. Self-updating.

## Install

1. Download `Voice-Tools-<version>-arm64.zip` from the
   [releases](https://github.com/brancusi/voice-tools-releases/releases/latest), unzip it, and move
   **Voice Tools.app** to Applications.
2. Open it. It's signed with a Developer ID and notarized by Apple, so it opens like any other app.
3. Allow **Microphone** and **Accessibility** when asked (Accessibility is needed to paste and to read selected
   text). The panel's **Checks** list shows anything missing, with a **Fix…** button for each.
4. Add your **OpenRouter** key (and optionally a **TypeSafe Jev** key) in **Open Voice Tools… → Setup**. Keys are
   stored in the Keychain.
5. Optional: System Settings → General → Login Items → add Voice Tools.

It checks for updates every 5 minutes; when one is out the menu bar icon becomes a download arrow and the panel
offers **Install…**. Permissions carry over between versions.

## A quick tour

- **Menu bar panel** — a launcher: your tracks (click to run), what's playing, the last few runs, and one line
  when something needs fixing.
- **Voice Tools window** (panel → *Open Voice Tools…*) — **Tracks** (build and edit pipelines), **History**
  (every run's text, kept on disk, searchable and copyable), **Vocabulary** (words transcription gets wrong, with training), **Setup**
  (checks, keys, on-device models, updates). While it's open the app is in the Dock and ⌘Tab.
- **HUD** — a small translucent tag at the bottom of the screen: `■ REC 00:04`, `PROC 312ms`, `OK 186ms`,
  `READ 42%`. It ignores the mouse.

## Documentation

| | |
|---|---|
| [User guide](docs/user-guide.md) | Tracks, triggers, every building block, Vocabulary and training, the HUD, Setup |
| [Architecture](docs/architecture.md) | How the code is organised and how a track runs, file by file |
| [Building and releasing](docs/releasing.md) | Local builds, signing, the release pipeline, secrets and keys |
| [Research and benchmarks](docs/research.md) | Every model comparison and measurement behind the defaults |
| [Gotchas](docs/gotchas.md) | macOS, OpenRouter, FluidAudio and Jev lessons learned the hard way |
| [Release notes](RELEASE_NOTES.md) | What changed in each version |

## Build

```sh
DEV=1 ./build.sh           # → build/Voice Tools.app, for local iteration
./build.sh                 # → dist/Voice-Tools-<VERSION>-arm64.zip
```

Needs macOS 14+ and Swift 6; the Command Line Tools are enough (no Xcode). Releases are cut by pushing a
`v<VERSION>` tag — see [Building and releasing](docs/releasing.md).

## Repositories

- [`brancusi/voice-tools`](https://github.com/brancusi/voice-tools) (private) — this source.
- [`brancusi/voice-tools-releases`](https://github.com/brancusi/voice-tools-releases) (public) — release zips and
  the update feed only.
