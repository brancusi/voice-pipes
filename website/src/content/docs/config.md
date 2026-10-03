---
title: "config.toml"
headline: "the config file"
nav: "Config file"
description: "Tracks, hotkeys and settings live in ~/.config/voice-pipes/config.toml, the vocabulary in vocabulary.toml. The format, every block including Branch, the reading and agent settings, checking and reloading, backups and secrets. Matches Voice Pipes 1.8.1."
order: 3
---

Everything you build in Voice Pipes is in two plain-text files you can edit, version and share:

| File | Holds |
| --- | --- |
| `~/.config/voice-pipes/config.toml` | Tracks, their hotkeys and blocks, and settings |
| `~/.config/voice-pipes/vocabulary.toml` | The words Fix words corrects |
| `config.schema.json`, `vocabulary.schema.json` | JSON Schemas beside them, so editors that read TOML schemas (such as VS Code with Even Better TOML) check as you type. In 1.8.1 the config schema doesn't describe `[settings.agents]` or `[settings.reading]` yet, so such an editor may flag those tables; `vp config check` is what the app goes by |
| `backups/` | Earlier versions of both files |

This page matches Voice Pipes **1.8.1**. `config.toml` is the app's setup, one to one: every track, block, branch
and hotkey the app's window shows is in it, with the [settings](#settings). Keys and secrets never are.

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
| `hotkeys` | A list of `{ keys = "…", mode = "hold" \| "toggle" }`. `keys` is modifiers (`control`, `option`, `shift`, `command`) then one key, joined with `+`: `a`–`z`, `0`–`9`, `space`, `return`, `tab`, `escape`, `delete`, `f1`–`f20`, `left`, `right`, `up`, `down`, and punctuation names such as `minus`, `equal`, `comma`, `period` or `slash`. `hold` records while held; `toggle` starts on one press and stops on the next. `hotkeys = []` leaves a track to the menu bar panel and `vp run` |
| `[[track.step]]` | One per block, in order. Each block takes the previous block's output |

The file also takes `version = 1` and the [settings](#settings) tables.

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
| `branch` | `question`, then `[[track.step.branch]]` entries, each with `name`, `when` and its own `[[track.step.branch.step]]` blocks. Jev answers the question and picks a branch by its `when`; that branch's blocks run, then the track carries on. Without a Jev key the first branch runs. [More below](#branch-one-track-several-paths) | text → what the branches give |
| `http` | `url`, `method` (`GET`, `POST`, `PUT`, `PATCH`), `headers = { … }`, `body`, `response_field`. `{{input}}` (URL-encoded in the url) or `{{input_json}}`; `${secret:name}` and `${env:NAME}` | text → text (the reply) |
| `template` | `template = "…{{input}}…"` | text → text |
| `paste` | `restore_clipboard = true` or `false`. Pastes at the cursor | text → text |
| `copy` | Leaves the text on the clipboard | text → text |
| `speak` | `model` = `pocket`, `supertonic`, `macos` or an OpenRouter speech model; `voice` (see `vp voices --model <model>`); `speed` = 0.6–2.0 | text → nothing |
| `show-hud` | Shows the text at the bottom of the screen | text → text |

`vp models --capability text|transcription|speech` lists the OpenRouter ids you can use, with OpenRouter's
prices. The app's model pickers show more for each model: what a paragraph costs, its speed on your Mac and a quality
rating ([choosing a model](#choosing-a-model)).

The rules `vp config check` enforces: `microphone` and `text` only start a track (not a branch); each block takes
what the one before it gives; and when a Branch's branches end differently (one speaks, another gives text), nothing
can follow the Branch, so put the remaining blocks inside each branch.

## Branch: one track, several paths

A `branch` block asks Jev a question about the text and runs the matching branch's own blocks before the track
carries on. Use it for different handling of different input: how hard or long the text is, what it's about, its
language, or whether it's a question or a note. Jev picks in about a third of a second. The starter Read aloud
(new installs since 1.7.0) starts with one:

```toml
  [[track.step]]
  type = "branch"
  question = "How hard is this text for a text-to-speech voice to read aloud correctly?"

    [[track.step.branch]]
    name = "easy"
    when = "Plain prose: ordinary words and sentences that any voice reads correctly as written."

    [[track.step.branch]]
    name = "medium"
    when = "Mostly prose with a few things a voice may misread: some numbers, times, prices, dates, units or common abbreviations."

      [[track.step.branch.step]]
      type = "llm"
      model = "google/gemini-2.5-flash-lite"
      prompt = "Rewrite the text so a text-to-speech voice reads it naturally. …"
      on_failure = "pass-through"

    [[track.step.branch]]
    name = "hard"
    when = "Dense or technical: code, commands, file paths, URLs, markdown, lists or tables, or many figures, symbols and acronyms."

      [[track.step.branch.step]]
      type = "llm"
      model = "anthropic/claude-haiku-4.5"
      prompt = "Rewrite the text so it can be read aloud and understood by ear. …"
      on_failure = "pass-through"
```

The prompts are shortened here; the app writes them in full. Then a `speak` block reads whatever the branch gave.

- **A branch with no blocks passes the text through**, as `easy` does.
- **Any block can go in a branch**, another `branch` included. Inputs (`microphone`, `text`) can't: a branch starts
  from text.
- **Give every branch a distinct, concrete `when`.** Jev chooses by it.
- **Without a Jev key, the first branch runs**, so a track keeps working (here: read as it is). The medium and hard
  branches also need an OpenRouter key for their LLM; with `on_failure = "pass-through"` a failed rewrite passes the
  text on unchanged.
- **Where the text goes:** with a Jev key, the text is sent to TypeSafe for the pick, and a branch's cloud blocks
  send it to OpenRouter. The `easy` branch and on-device voices keep it on your Mac.
- `vp tracks show <id>` lists the branches and their blocks (`2.medium.1`); `vp history show <n>` shows the pick,
  Jev's confidence and the branches not taken.

Existing setups keep their own Read aloud: an update doesn't rewrite your tracks. To get the branch, paste a
`branch` block like the one above into your Read aloud before its `speak` block, or ask your agent to.

A `route` is the simpler choice when every path is one LLM call: Jev picks which model answers. A `branch` picks a
whole run of blocks.

## Choosing a model

In the app, every block that uses a model (Transcribe, LLM, Speak, and each route) has one picker: the models on
your Mac first, then OpenRouter's live list for that job. For each model it shows:

| Column | What it is |
| --- | --- |
| Paragraph | What a typical job costs: 600 characters spoken, 150 tokens in and 150 out, or 30 s of audio. "—" when the price's billing unit isn't known; on-device models cost nothing |
| 1st sound, Reply or After stop | Speed on your Mac: the median of your last 20 runs of that model. On-device models show the app's own benchmark until you have runs; "—" when there's nothing yet |
| Quality | 1 to 5, from Artificial Analysis's public leaderboards (a snapshot from October 2026, shipped with the app); "not rated" where they don't cover a model |

Sort by **Best value** (quality for the price; the default), **Quality**, **Speed** or **Cost**; the sort is
remembered for each kind of model, and the models on your Mac stay on top in every sort. Tags say what a model can
do (such as multilingual, voice cloning, vision, or rate-limited for a free tier). Click a model for a sentence on what it's good at, then
**Use**. These are estimates and your own measurements, not a benchmark of every model. In config.toml a model is
just its id: `model = "anthropic/claude-haiku-4.5"`, or `parakeet`, `pocket`, `supertonic` and `macos`.

## Settings

The top of the file holds the settings, here with their defaults (the app writes each with a comment):

```toml
[settings]
appearance = "auto"            # auto (follow macOS) | daylight | sundown

[settings.agents]
read_aloud = "attention"       # off | long | attention | all
long_text = 600                # characters; longer than this counts as long

[settings.reading]
take_keys = "always"           # always | hover | click | never
click_away = "keep-reading"    # keep-reading | stop
stop = ["escape"]
pause = ["space"]
next = ["j", "down"]
previous = ["k", "up"]
slower = ["h", "minus"]
faster = ["l", "equal"]
start = ["g"]
end = ["shift+g"]

[settings.reading.global]
# none by default, e.g.
# faster = "control+option+right"
```

| Table | What it sets |
| --- | --- |
| `[settings]` | `appearance`: Auto follows your Mac, Daylight is light, Sundown is dark |
| `[settings.agents]` | What agents read aloud to you without being asked, and what counts as long (at least 50 characters). `vp agents read-aloud` sets it; [Agents](/docs/agents#what-agents-read-aloud) has what each mode means |
| `[settings.reading]` | When the HUD takes the keyboard while something is read aloud, what clicking another app does, and the keys for each action while the HUD has them (plain keys are fine: they only work then). `vp reading` sets it; [Reading aloud](/docs/reading) has the details |
| `[settings.reading.global]` | One shortcut per action that works in any app, but only while something is read. Give each a modifier (`control`, `option` or `command`): `vp config check` warns about one without (function keys aside) |

On its first launch, 1.8.1 moved setups from the old defaults to the new ones once: `take_keys = "hover"` became
`"always"` and `read_aloud = "off"` became `"attention"`. Any other value was kept, and you can set either back.

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
