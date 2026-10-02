---
title: "Developer docs"
nav: "Overview"
description: "Install Voice Pipes from a terminal and drive it with vp, its command-line tool: run voice pipelines, speak, listen, transcribe, and edit the config, from a shell or an agent."
order: 0
---

Voice Pipes is a Mac menu bar app that runs **tracks**: hotkey-triggered pipelines of blocks that transcribe, fix
your words, ask a model, paste, speak or call your own endpoint. These docs cover the developer side: installing
from a terminal, `vp`, the command-line tool, the config file, and the skill that teaches coding agents to use it.

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

That one line installs the app, links `vp` and installs the agent skill. Then:

```sh
vp
```

## Pages

| Page | What's in it |
| --- | --- |
| [Install](/docs/install) | Requirements, the one-line installer and its options, permissions you grant yourself, linking `vp` to an app you already have, updates and uninstalling |
| [CLI reference](/docs/cli) | Every `vp` command with its options and output, TOON and JSON, errors and exit codes, and how `vp` talks to the app |
| [Config file](/docs/config) | `config.toml` and `vocabulary.toml`: tracks, hotkeys, every block, checking, backups and secrets |
| [Agents](/docs/agents) | The skill for Claude Code, Codex and others, the optional session hook, and patterns for agents |

## What vp needs

- **The app.** `vp` is the Voice Pipes app's own binary, linked onto your `PATH`, so it needs the app installed
  and is always the same version. Commands that read or edit files work while the app is closed; the rest start it
  in the background.
- **A Mac** with Apple silicon and macOS 14 or later.
- **Your permission** for the microphone and Accessibility, granted once in the app's first-run window. macOS
  doesn't let a script grant them.
- **Keys only for cloud blocks.** Transcription with Parakeet, Fix words and the Pocket TTS and Supertonic voices
  run on your Mac with no account. OpenRouter and TypeSafe (Jev) keys unlock the cloud blocks:
  [what needs a key](/setup#what-needs-a-key).

New here as a user rather than a developer? The [home page](/) shows what tracks do, and [Setup](/setup) covers the
keys.
