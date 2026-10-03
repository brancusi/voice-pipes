---
title: "Agents"
headline: "vp for agents"
nav: "Agents"
description: "The Voice Pipes agent skill for Claude Code, Codex and other agents: what it teaches, what agents read aloud to you unasked, building tracks from plain language, the optional Claude Code session hook, and patterns. Matches Voice Pipes 1.8.1."
order: 5
---

`vp` is built so a coding agent can use it without help: compact TOON output (or `--json`), `help[]` lines with the
next commands, errors on stdout with a code and a hint, exit codes, and no prompts. The agent skill teaches agents
when and how to use it: to speak to you and ask you things, to read aloud what you want to hear, and to build or
change your tracks from a plain-language request.

## Install the skill

The [one-line installer](/docs/install#the-one-line-installer) and **Install command-line tool** in the app both
install it. On its own:

```sh
vp agents install
```

It writes `skills/voice-pipes/SKILL.md` into each agent folder that exists:

| Agent | Skill file |
| --- | --- |
| Claude Code | `~/.claude/skills/voice-pipes/SKILL.md` |
| Codex | `~/.codex/skills/voice-pipes/SKILL.md` |
| Others that read `~/.agents` | `~/.agents/skills/voice-pipes/SKILL.md` |

If none of those folders exist, it uses `~/.claude`. `vp agents` shows where the skill is installed.

The app keeps it current by itself. Each time it starts, it rewrites installed skills that are out of date, so they
match the installed `vp`, and gives the skill to agents you've installed since (a `~/.codex` that appeared, say) as
long as it's installed for at least one agent; after `vp agents uninstall` it stays uninstalled. This upkeep runs
only for a copy of the app in `/Applications` or `~/Applications`. This page matches the skill in Voice Pipes 1.8.1.

The skill ends with the full block and settings reference, generated from the same source as the one at the end of
config.toml, so the two always match.

## The Claude Code session hook (optional)

```sh
vp agents install --hook
```

Adds a `SessionStart` hook to `~/.claude/settings.json` that runs `vp agents context`, so each Claude Code session
starts with one line of Voice Pipes state: whether the app is running, the config's health, your track ids and
[what you want read aloud](#what-agents-read-aloud). It never starts the app. Your `settings.json` is backed up first, as `settings.json.voice-pipes-<date>.bak` beside it,
and everything else in it is kept; a file that isn't a JSON object is left alone with an error.

The hook runs `vp` by its full path. If you move the app, Voice Pipes repoints the hook, and any `vp` links to the
old location, the next time it starts. A link in a folder it can't write to (usually `/usr/local/bin`) shows up in
Setup → Checks as "vp points at a moved app", with **Fix…** to relink it (macOS asks for your password).

`vp agents uninstall` removes the skill and the hook. The hook doesn't speak: it only prints that one line.

## What the skill teaches

- **Start from live state.** At the start of a session: `vp` (the app, the config's health, your tracks) and
  `vp agents read-aloud` ([your standing preference](#what-agents-read-aloud)), followed for the whole session.
- **Talk to you.** `vp say "Tests passed; 3 files changed."` speaks and waits until it's done. Keep it short and
  plain: no markdown, code or URLs.
- **Ask you.** `vp ask "Deploy to staging or production?"` speaks the question, records your reply until you stop
  talking, and prints `answer:`. For a decision when you may not be at the screen.
- **Read you what you want to hear.** When you ask ("read this to me", "read me the summary"), and unasked as far as
  your read-aloud preference says. The agent writes a version for listening (plain spoken sentences and short
  paragraphs; no markdown, bullets, tables, code, file paths or URLs), runs `vp open reading` to show the
  follow-along card, pipes the text to `vp say`, and waits for it to return before speaking or asking anything else.
  You steer from the HUD and its keys ([Reading aloud](/docs/reading)); the agent can too: `vp next`, `vp prev`,
  `vp speed <0.6–2.0>`, `vp pause`, `vp resume`, `vp stop`, and `vp close reading` hides the card for later readings.
- **Run your tracks.** `vp tracks`, then `vp run <id> --text "…"`, which prints the final text. Tracks that end in
  Paste paste at your cursor, so the skill tells agents to prefer tracks without Paste unless you ask.
- **Build or change a track from a plain-language request**, by editing config.toml ([below](#build-a-track-from-plain-language)).
- **Change how Voice Pipes reads to you, when you ask.** "Only read me long stuff" → `vp agents read-aloud long`;
  "don't take my keys" → `vp reading keys hover` (or `click` or `never`); "always take them" → `always`. The skill
  says these are your preferences: change them only when you ask, then confirm in a sentence.
- **Show you, without screen access.** `vp open track <id> --step <n> --field prompt` opens the editor at that block
  with the cursor in the field, and it flashes. When an agent then edits config.toml, the open editor flashes what
  changed and opens the new or changed block, so you can watch a track being built.
- **Keys.** `vp status` and `vp auth` show keys only masked. Agents must never print, echo or log key values, or put
  them in config.toml (`vp secret set <name>` and `${secret:<name>}` instead). `vp auth login openrouter` needs you,
  in a browser.
- **Install.** If `vp` isn't found, the skill gives the one-line installer, and reminds the agent that you still
  have to grant Microphone and Accessibility yourself.

## What agents read aloud

Agents don't remember between sessions, so what you want read to you unasked is saved in config.toml
(`[settings.agents]`) and every agent and session reads it. Set it by telling an agent ("read me anything that needs
my attention", "stop reading things to me"), with `vp agents read-aloud <mode>`, or in **Setup → Command line and
agents → Agents read to me unasked**:

| Mode | Setup calls it | Agents read aloud |
| --- | --- | --- |
| `off` | Off | Only when you ask |
| `long` | Long replies | Long, rich text: a summary, report, plan, explanation or review longer than `long_text` characters (600 by default). Not short answers, code, diffs or logs |
| `attention` | When they need me | Everything `long` reads, plus anything that needs you: a question or decision they're waiting on, a finished task, a failure or blocker, in a sentence or two. **The default** since 1.8.1 |
| `all` | Everything | Every reply, as a short spoken version |

```sh
# What it is now
vp agents read-aloud

# Change it for every agent and session
vp agents read-aloud attention
vp agents read-aloud long --long-text 1000
```

The skill tells agents to read a spoken version, not the raw reply: what matters, in plain sentences, leaving code,
paths, diffs, tables and links on screen. They still write the full reply as text, and read one thing at a time.

This is guidance the agent follows, not something Voice Pipes enforces: the app doesn't watch your agent's replies.
Whether a reply counts as long, or needs you, is the agent's call. Once it decides, `vp say` reads exactly the text
it's given. For a rule that must fire every time (say, when a job ends), use a hook in your harness that pipes text to
`vp say`; Voice Pipes doesn't install one that speaks.

## Build a track from plain language

Ask for what you want ("make me a track that cleans up my dictation and posts it to my notes", "read hard text with
a cloud voice") and the skill walks the agent through it:

1. Work out what goes in (your voice, selected text, the clipboard), what should happen to it, where it goes
   (pasted, copied, spoken, posted somewhere) and the hotkey.
2. Look at what's there: `vp tracks`, `vp tracks show <id>` and config.toml itself. When changing a track, edit only
   what you asked for.
3. Write the blocks in config.toml, with a unique `id` and a hotkey nothing else uses. The skill carries every block
   and setting.
4. `vp config check`, and fix what it reports.
5. `vp open track <id>`, so you see each save flash in the editor.
6. Try it with `vp run <id> --text "sample"`, then `vp history show 1` for each step, Jev's pick and the cost. A
   track that pastes or speaks will do so; the skill asks agents to say so, or to test a copy without those blocks.
7. Tell you, in a sentence or two, what it built and its hotkey.

The skill also tells agents which block fits: [`branch`](/docs/config#branch-one-track-several-paths) when different
input needs different handling, `route` when only the answering model changes, `on_failure = "pass-through"` so an
LLM step can fail without stopping the track. It asks before changing or removing your existing tracks or hotkeys;
adding a new track is fine, and `vp config backups` and `vp config restore <n>` undo.

## Patterns

Start every session from live state and the user's read-aloud preference:

```sh
vp
vp agents read-aloud
```

In a script, read the preference as JSON:

```sh
mode=$(vp agents read-aloud --json | jq -r '.read_aloud')
```

Tell the user something when a long job ends:

```sh
npm test && vp say "Tests passed." || vp say "Tests failed. Check the terminal."
```

Read a long summary to the user, with the follow-along card. Write `$SUMMARY` for listening first:

```sh
vp open reading
printf '%s' "$SUMMARY" | vp say
```

`vp say` returns when the reading ends: finished, stopped from the HUD or with `vp stop`. Clicking a sentence in the
card carries on from there within the same `vp say`.

Get a decision out loud and use it. `--json` and `jq` keep it robust:

```sh
answer=$(vp ask "Deploy to staging or production?" --json | jq -r '.answer // empty')
```

Check the exit code, not just the text: `0` worked, `1` failed, `2` was bad usage. On failure stdout holds an
`error` object with `code`, `message` and `hint`:

```sh
if ! out=$(vp run clean-dictation --text "$draft" --json); then
  echo "$out" | jq -r '.error.code, .error.hint'
fi
```

Build a track while the user watches:

```sh
# 1. Add the [[track]] to ~/.config/voice-pipes/config.toml with its id, name and first block, then:
vp config check
vp open track voice-note
# 2. Add the remaining blocks; each save flashes in the open editor.
vp config check
vp run voice-note --text "remember to renew the cert"
# 3. How it ran, step by step, with what it cost
vp history show 1
```

## Install everything from an agent

An agent can install Voice Pipes on a Mac where it isn't installed, without prompts:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

The installer only installs a copy signed by Voice Pipes' developer and notarized by Apple. The person at the Mac
still has to grant Microphone and Accessibility in the first-run window; `vp open onboarding --step permissions`
brings that step forward, and `vp status` shows when both are granted. See [Install](/docs/install).
