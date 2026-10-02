---
title: "config.toml"
headline: "the config file"
nav: "Config file"
description: "Tracks, hotkeys and settings live in ~/.config/voice-pipes/config.toml, the vocabulary in vocabulary.toml. The format, every block, checking and reloading, backups and secrets."
order: 3
---

Everything you build in Voice Pipes is in two plain-text files you can edit, version and share:

| File | Holds |
| --- | --- |
| `~/.config/voice-pipes/config.toml` | Tracks, their hotkeys and blocks, and settings |
| `~/.config/voice-pipes/vocabulary.toml` | The words Fix words corrects |
| `config.schema.json`, `vocabulary.schema.json` | JSON Schemas beside them, so editors that read TOML schemas (such as VS Code with Even Better TOML) check as you type |
| `backups/` | Earlier versions of both files |

The path is always `~/.config/voice-pipes`, whatever `XDG_CONFIG_HOME` says: the app is started by launchd, which
doesn't see your shell's environment, so the app and `vp` would disagree otherwise. A `config.toml` symlinked from
your dotfiles stays linked. The app writes `config.toml` on its first launch, with a full block reference at the end (also printed by
`vp help config`).

## Edit, check, apply

1. Edit the file in any editor (`vp config open` opens it in your default one).
2. Check it: `vp config check`. It prints each problem with its line, where it is and, where it can, a "did you
   mean", and exits `1` if there are errors.
3. Save. **The app applies a save within a second.** A file that doesn't check out is not applied: the last good
   version keeps running, and Setup → Checks and the menu bar panel say what's wrong.

Edits made in the app's window are written back to the file in the same layout. Comments you add yourself aren't
kept when the app rewrites the file.

Undo with the backups: every change keeps the previous version (the newest 50 of each file).

```sh
# List them, newest first
vp config backups

# Put the newest one back
vp config restore 1
```

## A track

```toml
[[track]]
id = "fast-dictation"            # how `vp run` and agents name it
name = "Fast dictation"
color = "apricot"
hotkeys = [{ keys = "option+space", mode = "hold" }]

  [[track.step]]
  type = "microphone"

  [[track.step]]
  type = "transcribe"
  model = "parakeet"

  [[track.step]]
  type = "fix-words"

  [[track.step]]
  type = "paste"
```

| Key | Value |
| --- | --- |
| `id` | Required and unique: lowercase letters, digits and dashes. What `vp run <id>` uses |
| `name` | Required. Shown in the menu bar, the HUD and History |
| `color` | `apricot`, `dusk-blue`, `lavender`, `sage`, `marigold`, `rose`, `red-rock`, or `"#RRGGBB"` |
| `enabled` | `true` or `false`. A disabled track keeps its settings, but its hotkeys do nothing |
| `hotkeys` | A list of `{ keys = "…", mode = "hold" \| "toggle" }`. `keys` is modifiers (`control`, `option`, `shift`, `command`) then one key, joined with `+`: `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`, `f1`–`f20`, arrows and punctuation names such as `comma` or `slash`. `hold` records while held; `toggle` starts on one press and stops on the next |
| `[[track.step]]` | One per block, in order. Each block takes the previous block's output |

The file also takes `version = 1` and a `[settings]` table with `appearance = "auto" | "daylight" | "sundown"`.

## Blocks

Inputs give audio or text, `transcribe` turns audio into text, and the rest take text.

| `type` | Settings | Takes → gives |
| --- | --- | --- |
| `microphone` | | nothing → audio |
| `text` | `sources`: any of `"selection"`, `"page"`, `"clipboard"`, `"previous-clipboard"`; the first with text wins | nothing → text |
| `transcribe` | `model`: `"parakeet"` (on this Mac) or an OpenRouter id. Parakeet only: `mode` = `on-release`, `pause-chunks` or `streaming`, and `pause_ms` = 300–1200 for `pause-chunks` | audio → text |
| `fix-words` | Uses vocabulary.toml, on this Mac | text → text |
| `llm` | `model` (an OpenRouter id), `prompt` (`{{input}}` places the text; without it the text is the user message), `on_failure` = `pass-through` or `stop` | text → text |
| `route` | `[[track.step.route]]` entries, each with `name`, `when`, `model`, `prompt`. Jev picks one route by its `when`; without a Jev key the first route answers | text → text |
| `http` | `url`, `method` (`GET`, `POST`, `PUT`, `PATCH`), `headers = { … }`, `body`, `response_field`. `{{input}}` (URL-encoded in the url) or `{{input_json}}`; `${secret:name}` and `${env:NAME}` | text → text (the reply) |
| `template` | `template = "…{{input}}…"` | text → text |
| `paste` | `restore_clipboard = true` or `false`. Pastes at the cursor | text → text |
| `copy` | Leaves the text on the clipboard | text → text |
| `speak` | `model` = `pocket`, `supertonic`, `macos` or an OpenRouter speech model; `voice` (see `vp voices --model <model>`); `speed` = 0.6–2.0 | text → nothing |
| `show-hud` | Shows the text at the bottom of the screen | text → text |

`vp models --capability text|transcription|speech` lists the OpenRouter ids you can use, with prices.

## Secrets never go in the file

- Provider keys (OpenRouter, TypeSafe): `vp auth`, or the app's Setup. See [Setup](/setup).
- Your own tokens for `http` blocks: store them in the Keychain and reference them by name.

```sh
pbpaste | vp secret set notes
```

```toml
headers = { Authorization = "Bearer ${secret:notes}" }
```

`${env:NAME}` reads the app's own environment, which is launchd's, not your shell's: set it with
`launchctl setenv`, or use a secret.

## Example: a voice-notes track

Record a note with ⌥N, transcribe it on the Mac, fix your words and post it to your own endpoint:

```toml
[[track]]
id = "voice-note"
name = "Voice note"
color = "marigold"
hotkeys = [{ keys = "option+n", mode = "toggle" }]

  [[track.step]]
  type = "microphone"

  [[track.step]]
  type = "transcribe"
  model = "parakeet"

  [[track.step]]
  type = "fix-words"

  [[track.step]]
  type = "http"
  method = "POST"
  url = "https://api.example.com/notes"
  headers = { Authorization = "Bearer ${secret:notes}", "Content-Type" = "application/json" }
  body = '{"text": {{input_json}}}'
  response_field = ""
```

Then check it and try it with text instead of your voice:

```sh
vp config check
vp run voice-note --text "remember to renew the cert"
```

## vocabulary.toml

```toml
[[word]]
write = "Kubernetes"
heard_as = ["cuban eighties", "cube or netties"]
```

`write` is the spelling you want and `heard_as` lists what transcription writes instead. Fix words replaces whole
words only, ignoring case, on your Mac. An all-lowercase spelling gets a capital at the start of a sentence unless
you add `always_exact = true` (for words such as `kubectl`). From a terminal, `vp vocab add`, `remove` and `test` edit and try it, and
`vp vocab train` opens the app's training, where you say the word a few times ([CLI reference](/docs/cli#vp-vocab)).
