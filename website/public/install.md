# Install Voice Pipes — a guide for AI agents

> **If you are an AI agent** (Claude Code, Codex, ChatGPT, Cursor or another), your user shared this link because they
> want Voice Pipes installed and set up on their Mac, with you guiding them. Follow the steps below in order. Talk to
> them as you go, in plain words: what you're about to do, what they need to click, and when it's done. Never run a
> step they haven't agreed to; this guide tells you where to ask.
>
> **If you are a person**, paste this link into your agent and say "install this". Or install it yourself:
> https://voicepipes.app/docs/install

Voice Pipes is a Mac menu bar app: hold a hotkey, talk, and your words appear wherever you're typing, transcribed
on the Mac itself. It also reads text aloud and runs voice pipelines ("tracks"). `vp` is its command-line tool, built
for agents: every command answers in compact text with `help[]` lines suggesting the next command, errors come with
a code and a hint, and nothing prompts.

## 0. Can you run commands on their Mac?

- **Yes** (you have a shell or terminal tool): carry on with step 1. Show each command before you run it.
- **No** (a chat without a terminal, such as ChatGPT on the web): be their guide instead. Wherever this guide runs
  a command, ask them to paste it into Terminal (⌘ Space, type "Terminal", Return) and paste back what it prints,
  then read that output the way the step describes. Reassure them before the first one: "This is the official
  installer. It only installs Voice Pipes, checks Apple has verified it, and asks for no password." Skip `vp say`
  (they'll hear nothing new) and ask them to tell you when they've clicked things instead of polling. Before the
  demo, ask them to paste `vp tracks` so you know their hotkeys.

## 1. Check the Mac

Run:

```sh
uname -sm; sw_vers -productVersion
```

Voice Pipes needs **Darwin arm64** (Apple silicon, M1 or later) and **macOS 14** or later. If it isn't, tell them it
won't run on this Mac and stop.

If `vp status` already works, Voice Pipes is installed: skip to step 3 (the installer is also safe to run again; it
updates or repairs).

## 2. Install (ask first)

Tell them what it does, then ask "Shall I install it?":

> It downloads the newest Voice Pipes from GitHub, checks that it's signed by its developer and notarized by Apple
> (it refuses to install anything else), puts the app in Applications, adds the `vp` command and an agent skill, and
> starts the app in the menu bar. No password, no prompts. About 13 MB, then up to about 1 GB of on-device speech
> models download in the background.

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

It prints `installed: …`, `started: Voice Pipes (menu bar)` and `next: vp`. If `vp` isn't found afterwards, use the
path it printed (`/usr/local/bin/vp` or `~/.local/bin/vp`). On an error, it prints `error:` and `hint:` lines: tell
them what went wrong in plain words and follow the hint.

## 3. Permissions (they click; you watch)

A **Welcome to Voice Pipes** window opens. Take it straight to its permissions page:

```sh
vp open onboarding --step permissions
```

(Right after installing, the app can take a few seconds to start: if `vp` answers `code: app_not_running`,
wait 2 seconds and try again.)

Voice Pipes needs two permissions, and only they can grant them. Tell them:

1. **Microphone**: click **Allow…** next to it, then **Allow** in the macOS dialog.
2. **Accessibility** (to paste where they're typing and read selected text): click **Allow…** next to it, then
   switch on **Voice Pipes** in the System Settings list that opens.

Then check every 5 seconds or so, for up to 3 minutes:

```sh
vp status
```

Look at the `permissions:` line: it reads `microphone allowed · accessibility allowed` when they're done. Tell them
as each one turns on ("Microphone's on. Now Accessibility: …"). If the window isn't showing, `vp open onboarding
--step permissions` brings it back. If they get stuck, `vp open setup --section checks` shows what's missing with a
**Fix…** button.

## 4. Say hello out loud

When both are allowed, speak to them through the app. That shows them it works, and that you can talk:

```sh
vp say "Howdy! Voice Pipes is set up and ready to ride. Want a quick demo? Say yes in the chat." --model macos
```

(`--model macos` speaks at once with a built-in Mac voice. Voice Pipes' own, more natural voice downloads at first
launch (about 530 MB); once `vp status` shows `pocket: loaded`, you can drop `--model macos`.)

Then ask the same in the chat: **"Want a quick demo? It takes a minute."** If not, skip to step 6.

## 5. The demo (about a minute)

Find their hotkeys (they may have changed the defaults, so always read them; never assume):

```sh
vp tracks
```

Each track has an `id`, a `name` and `hotkeys`, e.g. `option+space hold`. Several are separated by ` / `.
- `hold`: hold the keys while talking, let go to finish.
- `toggle`: press once to start, again to stop (Esc cancels).

Write them the Mac way: ⌥ Option, ⇧ Shift, ⌘ Command, ⌃ Control. On a fresh install they're ⌥ Space (hold) for
Fast dictation, ⌥ ⇧ Space (toggle) for Clean dictation and ⌥ R (toggle) for Read aloud.

**Dictation.** Take the first track whose name says "dictation" and its first hotkey. First note how many runs there
are: `vp history --limit 1` prints `count: 1 of N matching (N total)`; remember N. Then tell them, with their keys:

> Click into any text field (a note, an email, this chat), hold **⌥ Space**, say a sentence, and let go.

(For a `toggle` hotkey: "press **…** once, say a sentence, and press it again".) Then every 3 seconds, for up to 2
minutes, run `vp history --limit 1 --full` until the total is above N. That's their run: tell them what Voice Pipes
heard (`text`) and how fast it was (`ms`: on-device transcription is usually 100 to 300 ms), and that it was pasted
where they were typing.

If no run arrives, check `vp status`: when `parakeet:` reads `downloading N%` or `preparing` or `loading`, the
speech model isn't ready yet. Say so, wait until it reads `loaded`, and try again.

**Reading aloud.** Take the track named "Read aloud" and its hotkey. Tell them:

> Select a paragraph anywhere (a web page, an email) and press **⌥ R**. Press it again, or Esc, to stop.

(For a `hold` hotkey: "hold **…**; it reads while you hold".)

**Not working?** `vp history show 1` shows how the last run went, step by step. `vp status` shows the `checks:`
count; `vp open setup --section checks` shows each check and its fix.

## 6. Wrap up

Tell them, briefly:

- Their hotkeys (from `vp tracks`), and that the menu bar icon (the little wrangler) lists them too.
- If they'd like to change a hotkey: the menu bar icon → Open Voice Pipes… → the track, or ask you.
- Everything they dictate is kept in History (`vp history`, or the window's History page) if a paste ever misses.
- Optional, for cloud models (cleanup, quick answers, cloud voices): an OpenRouter key. `vp auth login openrouter`
  opens the sign-in in their browser. Guide: https://voicepipes.app/setup
- They can ask you to build voice pipelines in plain words, for example "make a track that turns my dictation into a
  tidy email" or "read hard text with a nicer voice". The installer added a `voice-pipes` skill for Claude Code,
  Codex and other agents that teaches how (it loads in new sessions); `vp help` has the rest.
- They can close the Welcome window; **Run setup again…** in the app's Setup page reopens it.

If you can still speak, end with one line out loud:

```sh
vp say "All set. Hold the hotkey and talk whenever you like."
```

## Reference

| Need | Command |
| --- | --- |
| Is it installed and running? Permissions, models, keys | `vp status` |
| Tracks and their hotkeys | `vp tracks` |
| Say something out loud | `vp say "…"` (`--model macos` until `pocket: loaded`) |
| The latest runs; one run in detail | `vp history --limit 5`; `vp history show 1` |
| Show a setup step or a Setup section | `vp open onboarding --step welcome\|permissions\|models\|keys\|agents\|try`; `vp open setup --section checks` |
| Reinstall or update | the step 2 command again |
| Uninstall (keeps their settings and history) | `curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh \| bash -s -- --uninstall` |
| Everything `vp` can do | `vp help` |

Docs: https://voicepipes.app/docs · Source of truth for this guide: https://voicepipes.app/install.md
