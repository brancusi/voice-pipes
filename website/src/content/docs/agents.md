---
title: "Agents"
headline: "vp for agents"
nav: "Agents"
description: "The Voice Pipes agent skill for Claude Code, Codex and other agents, the optional Claude Code session hook, and patterns for agents that speak to you, ask you things and build tracks."
order: 4
---

`vp` is built so a coding agent can use it without help: compact TOON output (or `--json`), `help[]` lines with the
next commands, errors on stdout with a code and a hint, exit codes, and no prompts. The agent skill teaches agents
when and how to use it.

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

If none of those folders exist, it uses `~/.claude`. The app keeps installed skills up to date when it starts, so
they match the installed `vp`. `vp agents` shows where the skill is installed.

## The Claude Code session hook (optional)

```sh
vp agents install --hook
```

Adds a `SessionStart` hook to `~/.claude/settings.json` that runs `vp agents context`, so each Claude Code session
starts with one line of Voice Pipes state: whether the app is running, the config's health and your track ids. It
never starts the app. Your `settings.json` is backed up first, as `settings.json.voice-pipes-<date>.bak` beside it,
and everything else in it is kept; a file that isn't a JSON object is left alone with an error.

`vp agents uninstall` removes the skill and the hook.

## What the skill teaches

- **Talk to you.** `vp say "Tests passed; 3 files changed."` speaks and waits until it's done. Keep it short and
  plain: no markdown, code or URLs.
- **Ask you.** `vp ask "Deploy to staging or production?"` speaks the question, records your reply until you stop
  talking, and prints `answer:`. For a decision when you may not be at the screen.
- **Run your tracks.** `vp tracks`, then `vp run <id> --text "…"`, which prints the final text. Tracks that end in
  Paste paste at your cursor, so the skill tells agents to prefer tracks without Paste unless you ask.
- **Change the configuration safely.** Read config.toml and keep its layout, edit it, then always `vp config check`;
  undo with `vp config backups` and `vp config restore <n>`. Ask you before changing or removing your hotkeys or
  tracks (adding a track is fine). Never put keys or tokens in the file: `vp secret set <name>` and
  `${secret:<name>}` instead.
- **Show you, without screen access.** `vp open track <id> --step <n> --field prompt` opens the editor at that block
  with the cursor in the field, and it flashes. When an agent then edits config.toml, the open editor flashes what
  changed and opens the new or changed block, so you can watch a track being built.
- **Keys.** `vp status` and `vp auth` show keys only masked. Agents must never print, echo or log key values.
  `vp auth login openrouter` needs you, in a browser.
- **Install.** If `vp` isn't found, the skill gives the one-line installer, and reminds the agent that you still
  have to grant Microphone and Accessibility yourself.

## Patterns

Start every session from live state:

```sh
vp
```

Tell the user something when a long job ends:

```sh
npm test && vp say "Tests passed." || vp say "Tests failed. Check the terminal."
```

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
```

## Install everything from an agent

An agent can install Voice Pipes on a Mac where it isn't installed, without prompts:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

The installer only installs a copy signed by Voice Pipes' developer and notarized by Apple. The person at the Mac
still has to grant Microphone and Accessibility in the first-run window; `vp open onboarding --step permissions`
brings that step forward, and `vp status` shows when both are granted. See [Install](/docs/install).
