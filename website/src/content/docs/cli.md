---
title: "The vp command"
nav: "CLI reference"
description: "Every vp command with its options, inputs, outputs and errors, how vp talks to the app, and TOON and JSON output. Matches Voice Pipes 1.8.1."
order: 2
---

`vp` (also installed as `voicepipes`) runs Voice Pipes from a terminal: run tracks, speak, listen, transcribe, and
manage the config, vocabulary, keys and history. It is built to be driven by agents as well as people: compact
output, next-step hints, errors on stdout, and no prompts. Not installed yet? See [Install](/docs/install).

This page matches Voice Pipes **1.8.1**. On your Mac, `vp help` lists the commands and `vp <command> --help` shows
one command's usage and flags.

## At a glance

```sh
# Live state, then the details
vp
vp status

# Speak; ask out loud and print the spoken answer
vp say "Tests passed."
vp ask "Deploy to staging or production?"

# Read a long text with the follow-along card, then steer it from another shell
vp open reading
printf '%s' "$SUMMARY" | vp say
vp speed 1.4
vp next

# Send text through a track (Clean dictation then pastes it at your cursor)
vp run clean-dictation --text "um so the build is uh green"
git log -1 --format=%s | vp run read-aloud

# Transcribe a file on this Mac, see recent runs and one run's log, check the config
vp transcribe memo.m4a
vp history --limit 5
vp history show 1
vp config check

# What agents read aloud to you unasked, and when the HUD takes the keyboard
vp agents read-aloud attention
vp reading keys hover
```

The track ids above are the starter tracks'; `vp tracks` lists yours. Clean dictation's cleanup step uses an
OpenRouter model, so it needs your [OpenRouter key](/setup#openrouter).

## How vp works with the app

`vp` is the app's own binary, so it needs Voice Pipes installed, and it is always the same version as the app.
Commands that only read or edit files work without the app running. Everything else talks to the running app over
a private socket (`~/Library/Application Support/VoiceTools/control.sock`, readable only by you); if the app isn't
running, `vp` starts it in the background, without taking focus, and waits up to 20 seconds for it.

| Works without the app | Starts the app if needed |
| --- | --- |
| `vp`, `vp help`, `vp --version`, `vp status` (reports the config only) | `run`, `say`, `stop`, `pause`, `resume` |
| `tracks` (list, show, enable, disable) | `listen`, `ask`, `transcribe`, `watch` |
| `history` (list, show, usage) | `vocab train`, `config reload` |
| `vocab` (list, add, remove, test) | `models`, `voices` for macOS and OpenRouter voices |
| `config` (show, path, check, schema, backups, restore, open) | `auth`, `secret` |
| `voices` for `pocket` and `supertonic` | `open`, `close`, `ui`, `update` |
| `reading` (edits config.toml) | |
| `install`, `agents` (including `read-aloud`, which edits config.toml) | |

`vp speed`, `vp next` and `vp prev` are the exceptions: they change what's playing, so they never start the app and
fail with `app_not_running` when it isn't running. Commands that edit config.toml (`tracks enable`, `reading`,
`agents read-aloud`, `config restore`) work with the app closed; a running app picks the change up within a second.

The app runs one thing at a time. If a track, `vp say`, `vp listen` or a hotkey run is already going, a command that
needs it fails with `busy`; run `vp stop` or wait.

## Output

**TOON by default**, a compact format meant for agents and readable by people:

- `key: value` on each line; nested objects are indented.
- A list of rows is a header, `name[count]{field,field}:`, then one comma-separated row per line.
- A list of plain values is `name[count]: a,b,c`.
- Values are quoted only when they would be ambiguous (commas, colons, quotes, or text that looks like a number,
  `true`, `false` or `null`).
- Most commands end with `help[n]:` lines: the next commands worth running.

**`--json`** prints the same data as one JSON object (keys sorted) and drops the `help[]` lines. `vp watch --json`
prints one JSON object per event.

**`--full`** turns off truncation. Long text (a transcript in `vp history`, a detail in `vp status`) is cut with a
note such as `… (truncated, 812 chars total; use --full)`.

Both flags work anywhere before `--`. After `--`, everything is text: `vp say -- --json` speaks the word `--json`.

`vp config path` and `vp config schema` print plain text, and `vp help config` prints the config block reference.

```sh
vp --version
```

```text
version: 1.8.1
```

## Errors and exit codes

| Exit | Means |
| --- | --- |
| `0` | It worked |
| `1` | It failed: the app, a file or the request said no |
| `2` | Bad usage: an unknown command or flag, or a missing argument or value |

Errors are printed **on stdout**, like everything else, so an agent reading stdout sees them. Each has a stable
`code`, a `message` and usually a `hint`, the command to try next:

```sh
vp say
```

```text
error:
  code: missing_text
  message: Nothing to say.
  hint: "vp say \"Build passed\"   or   echo … | vp say"
```

With `--json`:

```json
{"error":{"code":"missing_text","hint":"vp say \"Build passed\"   or   echo … | vp say","message":"Nothing to say."}}
```

Unknown names get a suggestion where one is close, as in `No track 'clean'. (did you mean 'clean-dictation'?)`.
`vp config check` is the one command that prints a normal result and still exits `1`: when the file has errors.

The main codes:

| Code | When |
| --- | --- |
| `unknown_command`, `unknown_flag`, `unknown_subcommand` | A name `vp` doesn't know (exit 2) |
| `missing_argument`, `missing_value`, `missing_text`, `missing_question`, `missing_key`, `bad_value` | Something left out or malformed (exit 2 when `vp` itself catches it) |
| `app_not_found` | Voice Pipes.app isn't installed where `vp` expects it; the hint links the download |
| `app_not_running` | The app didn't start within 20 seconds |
| `app_closed` | The app closed the connection mid-request |
| `busy` | Something is already running; `vp stop` or wait |
| `no_such_track`, `invalid_track`, `takes_no_text`, `run_failed` | `vp run` problems; `run_failed` says which block failed |
| `no_microphone`, `no_speech`, `cancelled` | Recording: no permission or device, nothing heard, or stopped with `vp stop` or Esc |
| `bad_speed`, `bad_model`, `no_such_voice`, `speak_failed` | `vp say` and `vp ask` |
| `not_speaking` | `vp speed`, `vp next` or `vp prev` when nothing is being read aloud |
| `no_such_file`, `bad_audio` | `vp transcribe` or `vp config check` can't read the file |
| `config_invalid`, `vocabulary_invalid`, `vocabulary_unreadable` | The file doesn't check out; fix it, then retry |
| `no_such_backup` | `vp config restore` with a number that isn't in `vp config backups` |
| `no_such_provider`, `no_login`, `bad_name` | `vp auth` and `vp secret` |
| `no_such_target`, `no_such_section`, `no_such_field`, `no_such_step`, `no_such_route`, `not_a_route`, `no_such_word`, `no_such_run` | `vp open` can't find what you asked for |
| `exists` | `vp install` found another program with that name |
| `failed` | Anything else; the message says what |

## Arguments and input

- Flags take a value as `--max 20` or `--max=20`. A flag a command doesn't take is an error (exit 2), never ignored.
- `--help` after any command prints its usage and flags.
- **Text** for `vp run`, `vp say` and `vp ask` comes from, in order: the `--text` flag (`vp run` and `vp say`), the
  arguments after the command (joined with spaces), or standard input. Use `-` to read standard input explicitly.
  Piped text is read only if it arrives within 200 ms, so a shell that leaves standard input open and empty never
  hangs `vp`.
- **Keys and secrets** (`vp auth set`, `vp secret set`) take `--key` or `--value`, or a piped value. Prefer the pipe:
  a value on the command line can end up in your shell history.
- Nothing ever prompts. Anything that needs a person (granting a permission, signing in to OpenRouter in a browser,
  answering `vp ask`) says so.

## Commands

### vp

```sh
vp
```

Live state, without starting the app: the binary's path, whether the app is running (and its version), the config
file's health, your tracks as a table (`id`, `name`, `hotkeys`, `enabled`) and what to run next. Start here.

### vp status

```sh
vp status
```

With the app running: `app` (version), `permissions` (microphone and accessibility), `models` (the on-device
models), `keys` (each provider, whether it's set, the masked key), `checks` (counts of ok, info, warn and fail),
`problems` (each warning or failure with its detail), `config` health and, during a run, `running`.

Without the app it doesn't start it; it reports the config instead:

```text
app: not running
config: ~/.config/voice-pipes/config.toml · ok
tracks: 3
help[2]:
  Run `open -a "Voice Pipes"` (or any command that needs it starts it)
  Run `vp config check`
```

### vp tracks

```sh
# Every track: id, name, hotkeys, enabled
vp tracks

# One track's blocks: n, block, takes, gives
vp tracks show <id>

# Switch a track on or off (edits config.toml)
vp tracks enable <id>
vp tracks disable <id>
```

A track is named by its `id` from config.toml, or its name. `show` also says whether the track takes text
(`takes_text`), so you know whether `vp run <id> --text` will work.

A [Branch](/docs/config#branch-one-track-several-paths) block's branches and their blocks are listed under it as
rows of their own. In the starter Read aloud (new installs since 1.7.0) the Branch is step `2`; its branches are
`2.easy`, `2.medium` and `2.hard`, each with its `when` (or "passes the text through" when it has no blocks), and
the block inside the medium branch is `2.medium.1`. A branch inside a branch carries on the same way
(`2.hard.1.short`).

`enable` and `disable` edit config.toml (a backup is kept first) and answer with `changed: true` or `false`; a
disabled track keeps its settings, but its hotkeys do nothing.

### vp run

```sh
vp run <id> [--text "…" | -] [--max <seconds>] [--silence <seconds>]
```

Runs a track and prints the final text, the track and the total time in `ms`.

- **With text** (`--text`, arguments, or piped), it starts at the track's first block that takes text, skipping the
  microphone and transcription. A track with no such block fails with `takes_no_text`.
- **Without text**, a track that starts with the microphone records until you stop talking: `--silence` is how
  long a pause ends it (default 1.2 s) and `--max` caps the recording (default 30 s). Any other track runs from its
  first block, as its hotkey would.
- A track that ends in **Paste** pastes at your cursor, wherever it is. A track that ends in **Speak** speaks.
- How it ran lands in History: `vp history show 1` prints each block's time and output, which branch or route Jev
  picked, and what the run used and cost.

```sh
vp run clean-dictation --text "so um the deploy is uh done"
git log -1 --format=%s | vp run read-aloud
```

### vp say

```sh
vp say "…" [--model pocket|supertonic|macos|<openrouter-id>] [--voice <id>] [--speed 0.6–2.0]
```

Speaks text and returns when the reading ends, printing what was said, the `model` and `ms`. The default model is
Pocket TTS on your Mac. `supertonic` is the other on-device model, `macos` uses the system voices, and an OpenRouter
speech model id (for example `provider/model`) uses your OpenRouter key and is paid. `--speed` runs from 0.6 to 2.0
(default 1.0). `vp voices --model <model>` lists the voices.

```sh
vp say "Build passed. Three files changed."
vp say --model supertonic --speed 1.2 "Done."
cat notes.txt | vp say
```

Keep spoken text plain: markdown, code and URLs are read out literally.

While it reads, the HUD at the bottom of the screen shows the progress with pause and stop buttons, and its
follow-along card ([`vp open reading`](#vp-open-vp-close-vp-ui)) shows the whole text, a sentence per line, with the
word being spoken underlined (exact with `macos` voices, estimated with the others). Clicking a sentence there reads on
from it, with any voice, and `vp say` still returns only when the reading ends: when it finishes, or is stopped from
the HUD or with `vp stop`.

By default the HUD also takes the keyboard while it reads (Esc stops, Space pauses, j/k move a sentence, h/l change
the speed), without bringing Voice Pipes to the front. [Reading aloud](/docs/reading) has the keys and how to change
when the HUD takes them.

### vp listen

```sh
vp listen [--max <seconds>] [--silence <seconds>] [--model parakeet|<openrouter-id>]
```

Records from the microphone until you stop talking, then prints the transcript (`text`), the length of the
recording (`seconds`) and the transcription time (`ms`). Transcription is Parakeet on your Mac unless you name an
OpenRouter transcription model. Needs the Microphone permission. Fails with `no_speech` if it heard nothing.

### vp ask

```sh
vp ask "<question>" [--max <s>] [--silence <s>] [--voice <id>] [--voice-model <m>] [--speed <x>] [--listen-model <m>]
```

Speaks the question, records the reply until the speaker stops talking, and prints `question`, `answer` and
`seconds`. `--voice`, `--voice-model` and `--speed` are as in `vp say`; `--listen-model`, `--max` and `--silence`
as in `vp listen`. Made for an agent that needs a decision when you may not be looking at the screen.

```sh
vp ask "Should I deploy to staging or production?"
```

### vp transcribe

```sh
vp transcribe <audio-file> [--model parakeet|<openrouter-id>]
```

Transcribes any audio file macOS can read (WAV, M4A, MP3, AIFF and so on), on your Mac with Parakeet by default.
Prints `text`, `seconds` of audio and `ms`. The file never leaves the Mac unless you name an OpenRouter model.

### vp stop, vp pause, vp resume

```sh
# Stop speaking or recording; answers stopped: true or false
vp stop

# Pause reading aloud
vp pause

# Carry on
vp resume
```

### vp speed

```sh
vp speed <0.6–2.0>
```

Changes the speed of what's being read aloud, on the spot, with every kind of voice, and answers with the new
`speed`. It applies to this reading only: the next `vp say` uses its own `--speed` and a track its block's `speed`.
It rounds to tenths, like the **−** and **+** on the follow-along card. Fails with `not_speaking` when nothing is
being read, `bad_value` outside 0.6 to 2.0, and `app_not_running` when the app isn't running (it never starts it).

```sh
# From another shell while vp say is reading
vp speed 1.4
vp speed 0.8
```

### vp next, vp prev

```sh
# Jump to the next sentence of what's being read, or back one
vp next
vp prev
```

The same as clicking a sentence in the follow-along card, from a terminal. They answer with the `sentence` now
being read, how many there are (`of`) and the current `speed`. Like `vp speed`, they never start the app: they fail
with `not_speaking` when nothing is being read and `app_not_running` when the app isn't running.

### vp reading

```sh
# How readings are steered from the keyboard: when the HUD takes the keys, and which keys
vp reading

# When the HUD takes the keyboard while something is read aloud
vp reading keys always|hover|click|never

# Clicking another app while the HUD has the keys: carry on reading, or stop
vp reading click-away keep-reading|stop

# The keys for an action while the HUD has the keyboard (replaces its keys; one or more)
vp reading key faster period shift+equal

# A shortcut that works in any app, but only while something is read; none removes it
vp reading shortcut faster control+option+right
vp reading shortcut faster none

# Every reading setting back to its default, shortcuts included
vp reading reset
```

Edits `[settings.reading]` in config.toml (a backup is kept), so it works with the app closed; a running app picks
it up within a second. Every form answers with the settings as they now are: `keys`, `click_away`, and a
`bindings` table with each action's keys and its `anywhere` shortcut.

The actions are `stop`, `pause`, `next`, `previous`, `slower`, `faster`, `start` and `end`. Keys are written as in
[hotkeys](/docs/config#a-track) (`j`, `shift+g`, `equal`, `escape`). A shortcut for `vp reading shortcut` must
include `control`, `option` or `command`. What each mode does and the default keys: [Reading aloud](/docs/reading).

### vp watch

```sh
vp watch [--json]
```

Streams run events as they happen, from hotkeys and from `vp`, until you press Ctrl-C. TOON prints a header,
`events{at,event,track,detail}:`, then one row per event; `--json` prints one JSON object per line. Events are
`run.recording`, `run.processing`, `run.speaking`, `run.done` (with the text and `ms`) and `run.failed` (with the
error).

### vp history

```sh
# Recent runs, newest first
vp history [--limit <n>] [--track <id>] [--search <text>] [--since 30m|2h|3d]

# One run's log, step by step (1 is the newest)
vp history show <n> [--full]

# What your runs used and cost: today, 7 days, 30 days
vp history usage
```

Recent runs, read from the history file (the app keeps the last 1,000). The list shows `n`, when, the track, `ms`,
`cost` and the text (10 runs unless `--limit`). `cost` is `local` for a run that used nothing in the cloud, and blank
for runs from before 1.7.2, which have no log. `--since` takes a number and `s`, `m`, `h` or `d`.

`show <n>` prints one run: what was heard, the text, any failure, and its `log`, a row per block with its `ms`,
what it `used` and what it gave (`out`). Blocks inside a branch are indented under it; a Branch or Route row names
Jev's pick and the ones not taken. `used` is tokens and cost for LLMs and cloud transcription (as OpenRouter reports
them), characters and an estimate marked `≈` for cloud speech (priced from OpenRouter's list), and "on this Mac" for
local blocks. A block that failed says whether it stopped the run or passed its input on. `total` adds the run up.
Outputs are trimmed to 80 characters; `--full` shows them whole. Runs from before 1.7.2 show only each block's time.

Costs are what OpenRouter calls cost. Jev's picks (billed by TypeSafe) and your own HTTP blocks aren't counted.

`usage` is a table of `runs`, `tokens_in`, `tokens_out`, `cost` (exact) and `speech_estimate` (≈) for today, the
last 7 days and the last 30 days. It counts what's in History, so clearing History clears it too.

### vp vocab

```sh
# The words Fix words corrects
vp vocab

# Add a word with what it gets heard as; remove it
vp vocab add "Kubernetes" --heard "cuban eighties, cube or netties" [--exact]
vp vocab remove "Kubernetes"

# What Fix words would make of it
vp vocab test "we deploy on cube or netties"

# Opens training in the app
vp vocab train "Kubernetes"
```

Edits `~/.config/voice-pipes/vocabulary.toml` (a backup is kept). `add` on a word that's already there merges the
new mishearings in. `test` runs Fix words on a sentence without changing anything. `train` opens the app's word
training, where you say the word a few times; it needs the app and you.

### vp config

```sh
# Paths, health, appearance, number of tracks
vp config

# The path of config.toml, as plain text
vp config path

# Validate config.toml, or another file
vp config check [file]

# The JSON Schema
vp config schema [vocabulary]

# Dated copies, newest first
vp config backups

# Put backup n back
vp config restore <n>

# Make the app re-read both files now
vp config reload

# Open config.toml in your default editor
vp config open
```

`check` prints the `file`, a `result` (`ok`, `ok with warnings`, or `not valid: the app keeps the last good
version`) and a table of issues with `severity`, `line`, `where` and `problem`, including "did you mean" hints. It
exits `1` when there are errors, so it works as a gate in scripts. A file whose name starts with `vocabulary` is
checked as a vocabulary file. See [config.toml](/docs/config) for the format.

### vp models

```sh
vp models [--capability text|transcription|speech] [--search <text>] [--limit <n>]
```

OpenRouter models you can pick for a block, with prices: `id`, `name`, `price` (20 unless `--limit`;
`--capability` defaults to `text`). It also names what runs on this Mac for that job (`on_this_mac`): Parakeet for
transcription; Pocket TTS, Supertonic and macOS voices for speech.

### vp voices

```sh
vp voices [--model pocket|supertonic|macos|<openrouter-id>]
```

The voices for a speech model (default `pocket`): `id`, `name` and which is the `default`.

### vp auth

```sh
# Each provider: set or not, the masked key, what it's for
vp auth

# Sign in through your browser; the key is saved for you
vp auth login openrouter

# Prints a URL to open on any device…
vp auth login openrouter --headless

# …then the code OpenRouter shows (within 10 minutes)
vp auth login openrouter --code <code>

# A key from the clipboard
pbpaste | vp auth set typesafe

# Delete a key from the Keychain
vp auth remove openrouter
```

Provider keys live in your login Keychain, never in a file, and are never printed in full. The providers are
`openrouter` (cloud transcription, LLM and route models, cloud voices) and `typesafe` (Jev: Route steps and word
training); `jev` and `or` work as aliases. Only OpenRouter has a browser sign-in; set the TypeSafe key with
`vp auth set`. [Setup](/setup#openrouter) explains how to get each key and what needs one.

### vp secret

```sh
# The names you've set (never the values)
vp secret

# Store a token for your own endpoint
pbpaste | vp secret set notes

# Delete it
vp secret remove notes
```

Your own tokens for HTTP blocks, kept in the Keychain beside the provider keys. Use one in a block's url, headers or
body as `${secret:notes}`. Names use letters, digits, dashes and underscores.

### vp open, vp close, vp ui

```sh
# The main window
vp open

# A block's settings with the cursor in its prompt
vp open track clean-dictation --step 4 --field prompt

# A page, filtered or scrolled to what you name
vp open history --track fast-dictation --search "release"
vp open vocabulary --word "Kubernetes"
vp open setup --section connections
vp open onboarding --step permissions

# The menu bar panel
vp open menu

# The follow-along card for read-aloud, now and for later readings
vp open reading

# What's on screen now
vp ui

# Close every window, the panel and any sheet
vp close all
```

Shows any window, page, block or field, flashes it, and answers with what's on screen: the windows, the page, the
open block and the focused field. No screen recording or Accessibility access is involved.

| Target | Options |
| --- | --- |
| `main` (default) | |
| `track <id>` | `--step <n>` opens a block; `--route <n>` a route card in a Route block; `--field <name>` puts the cursor in a field (`name`, or a block's `prompt`, `url`, `headers`, `body`, `response_field`, `template`); `--section title\|triggers\|pipeline` |
| `history` | `--track <id>`, `--search <text>`, `--run <n>` (n from `vp history`) |
| `vocabulary` | `--word <word>`, `--add` |
| `setup` | `--section checks\|connections\|cli\|models\|appearance\|reading\|updates`, `--field <name>` (such as `openrouter-key`) |
| `onboarding` | `--step welcome\|permissions\|models\|keys\|agents\|try` |
| `reading` | The HUD's follow-along card: it shows with the current reading, or the next one, and stays open for later readings until closed |
| `menu`, `about`, `config` | `config` opens config.toml in your editor |

`--background` shows a window without taking the keyboard from the app you're in. `vp close` takes `main`, `menu`,
`reading`, `about`, `onboarding`, `sheet` (an open sheet) or `all`. `vp ui` also reports `reading` (`open`, `closed`,
or `open (shows when reading aloud)`) and, while something is read aloud, its `speed`.

### vp update

```sh
vp update
```

Asks the app to check for a new version now (it also checks every 5 minutes). If there is one, the menu bar panel
offers **Install…**.

### vp install

```sh
vp install [--dir <path>]
```

Links `vp` and `voicepipes` into `/usr/local/bin` if it's writable, else `~/.local/bin`, or `--dir`. Prints the
links, their `target` and whether the folder is `on_path`. It never replaces another program's file. See
[Install](/docs/install#link-vp-to-an-app-you-already-have).

### vp agents

```sh
# Where the skill is installed, and whether the session hook is
vp agents

# Install the skill (and the hook); remove both
vp agents install [--hook]
vp agents uninstall

# The one-line summary the session hook prints
vp agents context

# What agents read aloud to you without being asked
vp agents read-aloud [off|long|attention|all] [--long-text <chars>]
```

The agent skill and the optional Claude Code session hook. See [Agents](/docs/agents).

`read-aloud` on its own prints the standing preference every agent follows (`read_aloud`, what it `means`, and
`long_text`); with a mode or `--long-text` it saves it to `[settings.agents]` in config.toml, with the app open or
closed. The modes are `off` (only when you ask), `long` (long replies: summaries, reports, explanations),
`attention` (the default: long replies, plus anything that needs you, such as a question, a finished task or a
problem) and `all` (every reply). `--long-text` is how many characters count as long (default 600, at least 50).
It's a preference the skill tells agents to follow, not something the app enforces: see
[what agents read aloud](/docs/agents#what-agents-read-aloud).

### vp help

```sh
# Every command, with a one-line summary
vp help

# Usage, flags and the global flags
vp help <command>

# The config.toml block reference
vp help config
```
