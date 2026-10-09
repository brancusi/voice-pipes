# Voice Pipes

A macOS menu bar app for voice: dictate into any app, have text read aloud, or ask questions — each as a
**track**, a hotkey-triggered pipeline of building blocks you assemble yourself.

```
⌥ Space (hold)      Mic → Parakeet v3 (on this Mac) → Fix words → Paste             ~50–150 ms after you let go
⌥ ⇧ Space (toggle)  Mic → MAI-Transcribe-2 → Fix words → Claude Haiku cleanup → Paste  (OpenRouter)
⌥ R (toggle)        Selection / page / clipboard → Branch · Jev → Speak (Pocket TTS)    pause/resume with ⌥ R
```

Every block is swappable: transcription on this Mac or any OpenRouter model, cleanup with any LLM, speech from
on-device models, macOS voices or any OpenRouter voice, plus HTTP requests, templates, paste, copy and more.

Apple silicon, macOS 14 or later. Self-updating.

## Install

1. Download **[Voice-Pipes.dmg](https://github.com/brancusi/voice-tools-releases/releases/latest/download/Voice-Pipes.dmg)**
   (always the latest), open it, and drag **Voice Pipes** onto **Applications**.
2. Open it. It's signed with a Developer ID and notarized by Apple, so it opens like any other app, and lives in the
   menu bar.
3. The first time, **Set up Voice Pipes** walks you through it: Microphone and Accessibility (with a helper you can
   drag into Privacy & Security if the app isn't listed), the on-device models downloading in the background, and
   optional **OpenRouter** / **TypeSafe Jev** keys (stored in the Keychain). **Setup → Run setup again…** reopens it.
4. Optional: System Settings → General → Login Items → add Voice Pipes.

**From a terminal** (or for an agent): the app, the `vp` command and the agent skill in one go, no prompts:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

It downloads the latest DMG, refuses anything not signed by Voice Pipes' Developer ID and notarized, installs to
`/Applications` (or `~/Applications`), links `vp`, installs the skill for Claude Code, Codex and `~/.agents`, and
starts the app. Options go after `bash -s --`: `--apps-dir`, `--bin-dir`, `--version 1.6.2`, `--no-skill`,
`--no-launch`, and `--uninstall` (keeps your config and history). Run it again to reinstall or repair.

It checks for updates every 5 minutes; when one is out the panel offers **Install…**. Permissions carry over
between versions.

## Config and the command line

Tracks, hotkeys and settings live in `~/.config/voice-pipes/config.toml` (commented TOML with a JSON Schema; saves
apply within a second), the vocabulary in `vocabulary.toml` beside it. `vp`, the command-line tool (Setup → Install
command-line tool), runs tracks, speaks, listens, transcribes and manages keys, config and history, agent-first
(TOON output, `help[]` hints). An agent skill teaches Claude Code, Codex and others to use it. See the
[user guide](docs/user-guide.md#the-config-file).

## A quick tour

- **Menu bar panel** — a launcher: your tracks (click to run), what's playing, the last few runs, and one line
  when something needs fixing.
- **Voice Pipes window** (panel → *Open Voice Pipes…*) — **Tracks** (build and edit pipelines), **History**
  (every run's text, kept on disk, searchable and copyable), **Vocabulary** (words transcription gets wrong, with training), **Setup**
  (checks, keys, on-device models, updates). While it's open the app is in the Dock and ⌘Tab.
- **HUD** — a small translucent tag at the bottom of the screen: `■ REC 00:04`, `PROC 312ms`, `OK 186ms`,
  `READ 42%`. It never takes focus. While something is read aloud it has pause, stop and a read-along card, and
  takes the keys (Esc, Space, j/k, h/l) without bringing Voice Pipes forward.

## Documentation

| | |
|---|---|
| [User guide](docs/user-guide.md) | Tracks, triggers, every building block, Vocabulary and training, the HUD, Setup |
| [Architecture](docs/architecture.md) | How the code is organised and how a track runs, file by file |
| [Building and releasing](docs/releasing.md) | Local builds, signing, the release pipeline, secrets and keys |
| [Gotchas](docs/gotchas.md) | macOS, OpenRouter, FluidAudio and Jev lessons learned the hard way |
| [Website](website/README.md) | The voicepipes.app site: build, deploy, writing docs and blog posts |
| [Release notes](RELEASE_NOTES.md) | What changed in each version |

## Build

```sh
DEV=1 ./build.sh           # → build/Voice Pipes.app, for local iteration
./build.sh                 # → dist/Voice-Pipes-<VERSION>-arm64.zip
```

Needs macOS 14+ and Swift 6; the Command Line Tools are enough (no Xcode). Releases are cut by pushing a
`v<VERSION>` tag — see [Building and releasing](docs/releasing.md).

A local build isn't signed with the release Developer ID, so macOS treats it as a different app: it asks for
Microphone and Accessibility again and has its own Keychain entries.

## Repositories

- [`brancusi/voice-pipes`](https://github.com/brancusi/voice-pipes) — this source.
- [`brancusi/voice-tools-releases`](https://github.com/brancusi/voice-tools-releases) (public) — release zips and
  the update feed only.

## License

MIT — see [LICENSE](LICENSE). Bundled dependencies and fonts keep their own licences, listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). 
## Third-party models

Voice Pipes downloads its on-device models on first use; none are bundled. Parakeet TDT v3 (NVIDIA, CC-BY-4.0),
Pocket TTS (Kyutai, CC-BY-4.0) and Supertonic-3 (OpenRAIL++), via [FluidAudio](https://github.com/FluidInference/FluidAudio)'s
Core ML conversions. Check each licence before commercial use.
