# User guide

## Install from a terminal

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

Installs the app (checked: Developer ID and notarized), links `vp`, installs the agent skill and starts the app,
without asking anything, so an agent can run it too. Options after `bash -s --`: `--apps-dir <dir>`,
`--bin-dir <dir>`, `--version <x.y.z>`, `--no-skill`, `--no-launch`, `--uninstall` (removes the app, its `vp`
links and the skill; keeps config, history and keys). macOS still asks for Microphone and Accessibility on first
launch; those can't be granted from a script.

## First launch

**Set up Voice Pipes** opens the first time (and whenever a permission is missing until it's finished):

1. **Welcome.**
2. **Permissions:** Microphone (records while you hold or toggle a hotkey) and Accessibility (pastes at the cursor,
   reads the selection), each with a live status. **Open Settings…** opens the right Privacy & Security page and a
   small helper beside it; if Voice Pipes isn't in the Accessibility list, drag the helper's icon into the list, then
   switch it on. The helper closes itself once access is granted.
3. **Models:** Parakeet (with download progress) and Pocket TTS, downloading in the background from the moment the
   app starts; closing the window doesn't stop them.
4. **Keys (optional):** OpenRouter and TypeSafe Jev, pasted the same way as in Setup.
5. **Try it:** your hotkeys, and a box to dictate into.

**Setup → Run setup again…** reopens it any time.

## Tracks

A **track** is a pipeline: an input, any number of steps, and an output, started by one or more hotkeys. You
build tracks in **Open Voice Pipes… → Tracks**. Three come by default:

| Track | Trigger | Pipeline |
|---|---|---|
| Fast dictation | ⌥ Space, hold | Mic → Transcribe (Parakeet v3, on this Mac) → Fix words → Paste |
| Clean dictation | ⌥ ⇧ Space, toggle | Mic → Transcribe (MAI-Transcribe-2) → Fix words → LLM (Claude Haiku cleanup) → Paste |
| Read aloud | ⌥ R, toggle | Text (selection → page → clipboard) → Branch · Jev (easy / medium / hard) → Speak (Pocket TTS) |

Click a track in the menu bar panel to run it once without its hotkey. **Run now** in the editor does the same.

### Triggers

A track can have any number of hotkeys, each one of:

- **Toggle** — press to start, press again to stop.
- **Press & hold** — records while held; releasing stops it.

Esc cancels a recording. Pressing a track's trigger while it's **speaking** pauses, and again resumes from the
same word. A trigger that another app already owns, or that two tracks share, shows a warning in the editor and in
Setup → Checks. Modifier-only keys (like Right ⌘ alone) aren't supported.

### Building blocks

Every block declares what it takes and gives (`audio`, `text`, or nothing); the editor flags a block whose input
doesn't match the previous block's output. **+ Add step** lists them by category; drag a step by its ☰ handle
to reorder the pipeline.

| Block | Takes → gives | What it does |
|---|---|---|
| **Microphone** | — → audio | Records the default input at 16 kHz mono. Must be first. |
| **Text** | — → text | Uses the first source that has text: **Selected text** (via Accessibility, falling back to a ⌘C round trip for apps like Chrome), **Current page** (the focused window's web content), **Clipboard**, **Previous clipboard**. |
| **Transcribe** | audio → text | One block, one model list: **Parakeet v3 on this Mac** or any OpenRouter transcription model. Parakeet has a **Mode** — *On release* (default, most accurate), *Chunk at pauses*, *Streaming*. |
| **Fix words** | text → text | Instant find-and-replace from your **Vocabulary** (below). |
| **LLM** | text → text | Any OpenRouter language model with your instructions. `{{input}}` in the instructions places the text; otherwise the text is sent as the user message. Your Vocabulary is added as a glossary. **If this step fails**: pass the input through, or stop. |
| **Route · Jev** | text → text | Jev reads the text and picks one of your **routes** (about 0.3 s); that route's model answers with that route's instructions, like an LLM step. Each route has a name, a **Use when…** description (what Jev chooses by), a model and instructions. Starts with *quick* (Claude Haiku 4.5), *web* (Perplexity Sonar) and *deep* (Claude Sonnet 5.5). The HUD and Activity show the pick, e.g. `Jev 260 ms → web 100% · sonar`. Without a Jev key, the first route answers. |
| **Branch · Jev** | text → what the branches give | Jev answers your **question** about the text (about 0.3 s) and picks one **branch** by its **Use when…** description; that branch's own steps run (any blocks, even another branch), then the track carries on. A branch with no steps passes the text through. If branches end differently (one speaks, another gives text), the Branch must be the last block. Without a Jev key, the first branch runs. History lists the pick and each step the branch ran. |
| **HTTP request** | text → text | GET/POST/PUT/PATCH anywhere. `{{input}}` (URL-encoded in the URL) or `{{input_json}}` (a JSON string) in the URL or body; optional dotted path into a JSON response, e.g. `data.text`. |
| **Text template** | text → text | `{{input}}` / `{{input_json}}` substitution. |
| **Paste at cursor** | text → text | Pastes into the focused app with ⌘V, then restores your clipboard (optional). Waits for you to let go of the trigger's modifier keys first. |
| **Copy to clipboard** | text → text | Leaves the text on the clipboard. |
| **Speak** | text → — | One block, one model list: **Pocket TTS** or **Supertonic-3** on this Mac, **macOS voices**, or any OpenRouter speech model; then a voice (each with ▶ preview) and a speed. Long text is read in passages. |
| **Show in HUD** | text → text | Shows the text for a few seconds. |

Output blocks pass their text on, so a track can paste *and* POST, for example.

**Branching.** A Branch block turns a straight pipeline into a fork. Read aloud starts with one: Jev asks *"How
hard is this text for a text-to-speech voice to read aloud correctly?"* and picks **easy** (read as it is),
**medium** (a fast model, Gemini Flash-Lite, first spells out numbers, prices and dates, about 0.6 s) or **hard**
(Claude Haiku rewrites code, paths, URLs, markdown and tables into speakable sentences). Change any of it: give a
branch a cloud voice of its own, add a branch, or ask a different question (what the text is about, its
language, how long it is) and send each kind somewhere else.

### Choosing models

Transcribe, LLM and Speak have one **Model** picker: **On this Mac** first, then OpenRouter's live list for that
job (searchable, with prices; refreshed daily or from Setup). Switching a Speak model keeps your speed and keeps
the voice if the new model has it. You can also type any OpenRouter model id.

On-device models download once on first use and load when the app starts if a track uses them:

| Model | Kind | Size | Notes |
|---|---|---|---|
| Parakeet v3 | transcription | ~460 MB | ~50–150 ms after you stop speaking |
| Pocket TTS | speech | ~770 MB | Streams: first sound in ~20 ms. 26 voices. Kyutai research licence — check before commercial use. |
| Supertonic-3 | speech | ~100 MB + voices | ~80× faster than real time. 10 voices (Female/Male 1–5). Apache-2.0. |

## Vocabulary and Fix words

**Open Voice Pipes… → Vocabulary** holds words transcription keeps getting wrong. Each row:

- **Write** — the spelling you want, e.g. `Claude Code`.
- **Heard as** — what comes out instead, comma-separated, e.g. `cloud code, clawed code`.
- **Always exact** — for all-lowercase spellings that must never be capitalised (`kubectl`).

**Fix words** replaces them mechanically — no model, nothing leaves the Mac, effectively zero time:

- Whole words only (`cloud coder` is left alone), any capitalisation, extra spaces tolerated, punctuation and
  possessives kept (`Claude Code's`). The longest listed phrase wins where entries overlap.
- Matching ignores case; your text is never lowercased — only the matched span is replaced.
- A spelling with any capital (`OpenRouter`, `macOS`) is always written exactly. An all-lowercase spelling gets a
  capital first letter at the start of a sentence, unless **Always exact** is on.
- It can't tell intent: if you list `cloud code` and genuinely mean "cloud code", it's still replaced. List only
  phrases you never mean literally.

The **Try it** box shows the result as you type. LLM steps receive the list as a glossary, so cleanup keeps your
spellings too. The list lives in `~/Library/Application Support/VoiceTools/vocabulary.json`.

### Training a word

**Train…** on a row collects the ways transcription mishears that word:

1. **Start takes**, say the word; **Next take** (Space) ends that take and starts the next with the microphone
   still open; **Finish** (Return) ends the last. About five takes, varied a little, works well. A level meter shows
   it's hearing you; silent or too-short takes are rejected.
2. Optionally have the on-device voices say it too (36 voices at two speeds).
3. **Train**: each take is replayed about 30 ways (5 speeds × 2 volumes × 3 noise levels) through Parakeet; every
   distinct result is listed with how often it came up, and you see how often it was already right. Five takes take
   about 5 seconds; with the voices, about 30 seconds the first time.
4. With a **TypeSafe Jev** key (Setup), each result is judged: how safe is it to replace everywhere? Garbled
   versions of the word score high (green, pre-ticked at 60%+); real words, other names and specialist terms score
   low. Without a key, results that came up twice and aren't ordinary dictionary words are pre-ticked.
5. **Add to Heard as**. The results list ticks a row with one click anywhere on it; hover a row for where each result
   came from (your takes or the voices).

Tip: if your first name comes out right and the surname doesn't, add and train the surname as its own entry too.

## The menu bar icon

The Wrangler, the Voice Pipes cowboy, in his hat. While you're recording he raises an arm and swings a lasso over
his hat. A dot appears when an update is waiting, a speaker shows while something is read aloud, and a warning
triangle means Setup needs attention.

**Appearance** (Setup → Appearance): **Auto** follows your Mac, **Daylight** is always light (bone paper and ink),
**Sundown** is always dark (desert earth, sunset accents). The HUD stays dark either way.

## The HUD

A slim tag at the bottom of the screen. It never takes focus from the app you're in, and ignores clicks except for
its read-aloud buttons.

| Tag | Meaning |
|---|---|
| `■ REC 00:04` + level bars | Recording |
| `■ REC 00:11 …your words▌` | Recording with a streaming or chunked Parakeet mode: the words so far, with a cursor |
| `PROC 312ms` | Processing since you let go |
| `OK 186ms` | Done — total processing time; fades in under a second |
| `READ 42%` / `PAUSED 42%` / `VOICE ···` | Reading aloud / paused / preparing the voice, with **⏸/▶** and **⏹** buttons (pressing the track's hotkey again also pauses and resumes) |
| `ERR …` | What went wrong (stays a few seconds) |

**Follow along.** While anything is read aloud, the tag's third button (☰) opens a card above it with the whole
text, a sentence per line: the one being read is lit with a lavender bar, finished ones dim, and the card scrolls
with the voice, with a thin underline running under the word being spoken (exact with macOS voices, estimated with
the others). Click any sentence to read from there. Hold the pointer over the card to scroll ahead; it follows the
voice again when the pointer leaves.
**−** and **+** change the speed live (0.6–2×, for this reading only; the track's speed stays as set). The card
stays open for later readings until you close it (˅). From a terminal: `vp open reading`, `vp close reading`,
`vp speed 1.4`.

Under the tag, a second line names the model answering, once an LLM or Route step has run: for Route · Jev, the
route, its model, and Jev's time and confidence, e.g. `quick → claude-haiku-4.5 · Jev 262 ms 100%`.

The full text and per-step timings of every run are in **History**.

## History

Everything a track produces is kept, so a dictation that went nowhere (you clicked away, the paste had no text
field) is never lost. The menu bar panel shows the last three runs with a copy button each; **All N →** opens
**History** in the Voice Pipes window, where you can search everything, copy any run back to the clipboard, and see
each step's time. A run that failed partway keeps the text it had, marked with what went wrong. When later steps
changed what you said (a question and its answer, dictation and its cleanup), what transcription heard is shown
above the result. Runs are grouped by day; the chips next to the search box filter by track, and each run's steps
are listed in order with their times, coloured by kind (transcription blue, transforms lavender, outputs green). The
last 1,000 runs are kept; **Clear history…** removes them all.

## About

**About Voice Pipes** (the ⓘ button in the menu bar panel's footer, or the app menu while the window is open) shows
the version, your first few hotkeys, **Release notes** and **Check for updates**.

## Setup

- **Checks** — Microphone, Accessibility, Parakeet, on-device voices, OpenRouter key (validated live), shortcut
  clashes, track errors. **Fix…** on a permission clears any stale entry macOS kept from an older build, asks
  again and opens the right Settings page. **Copy report** puts a plain-text summary on the clipboard.
- **Connections** — OpenRouter and TypeSafe (Jev), each with what it's used for and a status (OpenRouter's key is
  checked live). A saved key shows masked, e.g. `sk-or-v1-••••••••••••3f9a`. To replace it, click the field and
  paste: the new key is saved to the Keychain at once, with no Save button (or type it and press Return; Esc
  leaves it as it was). **Remove key** deletes it. OpenRouter's model list and **Reload models** sit here too. Jev
  is used by Route steps and vocabulary training.
- **On this Mac** — status of Parakeet, Pocket TTS and Supertonic-3, with **Load now**.
- **Updates** — version and **Check now**.

## The config file

Everything you build lives in **`~/.config/voice-pipes/config.toml`** (tracks, hotkeys, settings) and
**`vocabulary.toml`** beside it, readable and commented, with JSON Schemas (`config.schema.json`,
`vocabulary.schema.json`) so editors such as VS Code with Even Better TOML check them as you type. The full block
reference is at the end of `config.toml` (and `vp help config`).

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
```

- **Saves apply within a second.** A file that doesn't check out is not applied: the last good version keeps running,
  and Setup → Checks (and the panel) say what's wrong, with the line and a "did you mean" where it can.
  `vp config check` checks without applying.
- **Edits in the window write the file back** in the same layout and comments. Comments you add yourself aren't kept.
- **Backups:** every change keeps the previous version in `backups/` (the newest 50 of each file);
  `vp config backups` and `vp config restore <n>`.
- **Secrets never go in the file.** Provider keys: `vp auth`. Your own tokens for http blocks:
  `vp secret set <name>`, then `${secret:<name>}` in a url, header or body (`${env:NAME}` reads the app's own environment, which is launchd's, not your shell's: set it with `launchctl setenv` or use a secret).
- Upgrading from 1.5 moves your tracks and vocabulary into these files once; the old JSON files stay as last-good copies.

## The command line: `vp`

**Setup → Command line and agents → Install command-line tool** (also a step in the setup window) links `vp` (and
`voicepipes`) into `/usr/local/bin` (macOS asks for your password once) or, if you decline, `~/.local/bin`; from a
terminal, `vp install` does the same without a password. It's the app's own binary, so it's always the same version.

Run `vp` alone for live state. Output is TOON by default (compact, for agents; `--json` for JSON), long text is
truncated unless `--full`, errors print on stdout with a code and a hint, and exit codes are 0 (ok), 1 (error),
2 (bad usage). Nothing prompts. Commands that only read or edit files work without the app; the rest start it in
the background.

| Command | Does |
|---|---|
| `vp` | Live state: the app, config health, tracks, what to run next |
| `vp status` | Permissions, on-device models, keys (masked), problems |
| `vp tracks` · `tracks show <id>` · `tracks enable/disable <id>` | List, inspect, switch tracks on or off |
| `vp run <id> [--text "…"]` | Run a track. Text (or piped text) starts at its first block that takes text; a microphone track without text records until you stop talking. Prints the final text |
| `vp say "…" [--model --voice --speed]` | Speak (default Pocket TTS on this Mac) |
| `vp listen` · `vp ask "<question>"` | Record until you stop talking and print the transcript; `ask` speaks the question first |
| `vp transcribe <file>` | Transcribe an audio file on this Mac (or `--model <openrouter-id>`) |
| `vp stop` · `pause` · `resume` | Control speech and recording |
| `vp history [--limit --track --search --since]` · `history show <n>` | Recent runs with timings |
| `vp vocab [add/remove/test/train]` | The Fix words list |
| `vp config [check/schema/backups/restore/reload/open/path]` | The config file |
| `vp models --capability text\|transcription\|speech` · `vp voices --model <m>` | What you can pick |
| `vp auth [login openrouter / set <provider> / remove <provider>]` | Keys (Keychain). `login openrouter` signs in through the browser; `--headless` then `--code <code>` without one |
| `vp secret [set/remove]` | Your own secrets for http blocks |
| `vp watch` | Stream run events as they happen |
| `vp open <target> [--step --route --field --section --track --search --run --word --add --background]` | Show any window, page, block or field: `main`, `menu` (the menu bar panel), `track <id>`, `history`, `vocabulary`, `setup`, `onboarding`, `about`, `config`. What it points at flashes; it answers with what's on screen |
| `vp close <target>` · `vp ui` | Close `main`, `menu`, `about`, `onboarding`, an open `sheet`, or `all`; print what's on screen |
| `vp update` | Check for updates |
| `vp install` · `vp agents install [--hook]` | Put vp on your PATH; install the agent skill |

## Agents

`vp agents install` (also done by **Install command-line tool**) writes a skill for coding agents into each agent's
folder that exists: `~/.claude/skills/voice-pipes/` (Claude Code), `~/.codex/skills/voice-pipes/` (Codex) and
`~/.agents/skills/voice-pipes/`. It teaches them to speak to you (`vp say`), ask you something out loud and use your
answer (`vp ask`), run your tracks, and edit `config.toml` safely (always `vp config check`, never keys in the file).
The app keeps installed skills up to date. `vp agents install --hook` also adds a Claude Code session hook that
shows Voice Pipes' state at the start of each session (your `~/.claude/settings.json` is backed up first);
`vp agents uninstall` removes both.

Updates take care of the rest: `vp` is a link to the app's own binary, so it's always the app's version. At each
launch the app rewrites installed skills that are out of date, installs the skill for agents set up since (if it's
installed for any agent), points the session hook at the current `vp`, and repoints `vp` links if you moved the app
(a root-owned link it can't change shows up in Setup → Checks with **Fix…**).

Agents can show you what they're doing without screen access: `vp open track <id> --step 3 --field prompt` opens the
editor at that block with the cursor in its instructions. When an agent edits `config.toml`, the open editor flashes
what changed and opens a single new or changed block, so you can watch a track being built.

## Your data

| Where | Contents |
|---|---|
| `~/.config/voice-pipes/config.toml` | Tracks, hotkeys, settings (see above) |
| `~/.config/voice-pipes/vocabulary.toml` | The Vocabulary list |
| `~/.config/voice-pipes/backups/` | Earlier versions of both |
| `~/Library/Application Support/VoiceTools/history.json` | History: the last 1,000 runs' text, what was heard, timings. **Clear history…** empties it |
| `~/Library/Application Support/VoiceTools/tracks.json`, `vocabulary.json` | Last-good copies the app falls back on |
| `~/Library/Application Support/VoiceTools/models-cache.json` | OpenRouter's model list (refreshed daily) |
| `~/Library/Application Support/VoiceTools/control.sock` | How `vp` talks to the app (only you can open it) |

On-device models are cached by FluidAudio in `~/Library/Application Support/FluidAudio/Models/`. API keys and your
secrets are in the login Keychain under `io.github.brancusi.voice-tools`.
