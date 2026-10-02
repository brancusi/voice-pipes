# User guide

## Tracks

A **track** is a pipeline: an input, any number of steps, and an output, started by one or more hotkeys. You
build tracks in **Open Voice Pipes… → Tracks**. Three come by default:

| Track | Trigger | Pipeline |
|---|---|---|
| Fast dictation | ⌥ Space, hold | Mic → Transcribe (Parakeet v3, on this Mac) → Fix words → Paste |
| Clean dictation | ⌥ ⇧ Space, toggle | Mic → Transcribe (MAI-Transcribe-2) → Fix words → LLM (Claude Haiku cleanup) → Paste |
| Read aloud | ⌥ R, toggle | Text (selection → page → clipboard) → Speak (Pocket TTS) |

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
| **HTTP request** | text → text | GET/POST/PUT/PATCH anywhere. `{{input}}` (URL-encoded in the URL) or `{{input_json}}` (a JSON string) in the URL or body; optional dotted path into a JSON response, e.g. `data.text`. |
| **Text template** | text → text | `{{input}}` / `{{input_json}}` substitution. |
| **Paste at cursor** | text → text | Pastes into the focused app with ⌘V, then restores your clipboard (optional). Waits for you to let go of the trigger's modifier keys first. |
| **Copy to clipboard** | text → text | Leaves the text on the clipboard. |
| **Speak** | text → — | One block, one model list: **Pocket TTS** or **Supertonic-3** on this Mac, **macOS voices**, or any OpenRouter speech model; then a voice (each with ▶ preview) and a speed. Long text is read in passages. |
| **Show in HUD** | text → text | Shows the text for a few seconds. |

Output blocks pass their text on, so a track can paste *and* POST, for example.

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
5. **Add to Heard as**.

Tip: if your first name comes out right and the surname doesn't, add and train the surname as its own entry too.

## The menu bar icon

Three little organ pipes behind a `›` prompt. They jump while you're recording, a dot appears when an update is
waiting, a speaker shows while something is read aloud, and a warning triangle means Setup needs attention.

The app follows your Mac's appearance: **Sundown** (dark earth, sunset accents) or **Daylight** (bone paper and
ink). The HUD stays dark either way.

## The HUD

A slim tag at the bottom of the screen. It never takes focus from the app you're in, and ignores clicks except for
its read-aloud buttons.

| Tag | Meaning |
|---|---|
| `■ REC 00:04` + level bars | Recording |
| `PROC 312ms` | Processing since you let go |
| `OK 186ms` | Done — total processing time; fades in under a second |
| `READ 42%` / `PAUSED 42%` / `VOICE ···` | Reading aloud / paused / preparing the voice, with **⏸/▶** and **⏹** buttons (pressing the track's hotkey again also pauses and resumes) |
| `ERR …` | What went wrong (stays a few seconds) |

Under the tag, a second line names the model answering, once an LLM or Route step has run: for Route · Jev, the
route, its model, and Jev's time and confidence, e.g. `quick → claude-haiku-4.5 · Jev 262 ms 100%`.

The full text and per-step timings of every run are in **History**.

## History

Everything a track produces is kept, so a dictation that went nowhere (you clicked away, the paste had no text
field) is never lost. The menu bar panel shows the last three runs with a copy button each; **All N →** opens
**History** in the Voice Pipes window, where you can search everything, copy any run back to the clipboard, and see
each step's time. A run that failed partway keeps the text it had, marked with what went wrong. When later steps
changed what you said (a question and its answer, dictation and its cleanup), what transcription heard is shown
above the result. The last 1,000 runs are kept; **Clear history…** removes them all.

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

## Your data

All under `~/Library/Application Support/VoiceTools/` and safe to edit while the app is **quit**:

| File | Contents |
|---|---|
| `tracks.json` | Tracks, triggers and steps. If it can't be read it's moved aside as `tracks.unreadable-<time>.json`, never overwritten. |
| `vocabulary.json` | The Vocabulary list. |
| `history.json` | History: the last 1,000 runs' text, what was heard, timings. Plain text on your disk; **Clear history…** empties it. |
| `models-cache.json` | OpenRouter's model list (refreshed daily). |
| `supertonic-voices/` | Downloaded Supertonic voice styles. |

On-device models are cached by FluidAudio in `~/Library/Application Support/FluidAudio/Models/`. API keys are in
the login Keychain under `io.github.brancusi.voice-tools` (accounts `openrouter`, `typesafe`).
