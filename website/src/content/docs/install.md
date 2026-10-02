---
title: "Install from a terminal"
nav: "Install"
description: "Install Voice Pipes, the vp command and the agent skill with one line, or link vp to an app you already have. Requirements, options, what the installer checks, permissions, updates and uninstalling."
order: 1
---

`vp` is not a separate download. It is the Voice Pipes app's own binary, linked onto your `PATH` under the names
`vp` and `voicepipes`, so it is always the same version as the app and needs the app installed. There are three
ways to get it:

| You have | Do this |
| --- | --- |
| Nothing yet | [The one-line installer](#the-one-line-installer): the app, `vp` and the agent skill |
| The app, installed from the DMG | [Link `vp` to it](#link-vp-to-an-app-you-already-have), from the app or a terminal |
| An agent that should set it up | The same one line: it asks nothing ([agents](/docs/agents)) |

## Requirements

- A Mac with Apple silicon (M1 or later).
- macOS 14 Sonoma or later.
- A terminal with `curl` and `bash` (both come with macOS).

The installer stops with an error on anything else: "Voice Pipes is a Mac app", "needs an Apple silicon Mac" or
"needs macOS 14 Sonoma or later".

## The one-line installer

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

It installs the newest release, links `vp`, installs the agent skill and starts the app in the menu bar. It never
prompts and never uses `sudo`, so an agent can run it too. Run it again at any time to reinstall or repair.

Prefer to read a script before running it? Download it, look, then run it:

```sh
curl -fsSL -o install.sh https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh
less install.sh
bash install.sh
```

### What it does, in order

1. Checks the Mac: macOS, Apple silicon, version 14 or later.
2. Downloads `Voice-Pipes.dmg` from the public
   [releases](https://github.com/brancusi/voice-tools-releases/releases) and opens it read-only.
3. **Refuses anything that isn't Voice Pipes:** the app's code signature must verify, it must be signed by Voice
   Pipes' Developer ID, and Gatekeeper must accept it (notarized by Apple). If any check fails, nothing is replaced.
4. Quits the copy it is about to replace, if that copy is running (other copies are left alone).
5. Copies the new app beside the old one, then swaps them, so a failed copy never leaves you without the app.
6. Links `vp` and `voicepipes` ([where](#where-things-go)).
7. Installs the [agent skill](/docs/agents) for Claude Code, Codex and `~/.agents`.
8. Starts Voice Pipes in the background and prints `next: vp`.

### Options

Options go after `bash -s --`:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash -s -- --no-launch
```

| Option | Does |
| --- | --- |
| `--apps-dir <dir>` | Where the app goes. Default: where it is now, else `/Applications`, else `~/Applications` |
| `--bin-dir <dir>` | Where `vp` and `voicepipes` are linked. Default: `/usr/local/bin` if you can write to it, else `~/.local/bin` |
| `--version <x.y.z>` | A specific release instead of the newest (a leading `v` is fine). `vp` exists from 1.6.0 |
| `--no-skill` | Don't install the agent skill |
| `--no-launch` | Don't start the app afterwards. A copy that was already running is started again either way |
| `--uninstall` | Remove the app, its `vp` links and the skill ([below](#uninstall)) |
| `-h`, `--help` | Print the options |

Exit codes: `0` ok, `1` failed, `2` bad usage. Failures print `error:` and, where there is one, a `hint:` line.

### Where things go

| What | Where |
| --- | --- |
| The app | `/Applications/Voice Pipes.app`, or `~/Applications` if `/Applications` isn't writable |
| `vp`, `voicepipes` | Symlinks in `/usr/local/bin` if writable, else `~/.local/bin` |
| The agent skill | `skills/voice-pipes/SKILL.md` in `~/.claude`, `~/.codex` and `~/.agents`, whichever exist (`~/.claude` if none do) |
| Your config | `~/.config/voice-pipes/` ([config](/docs/config)) |

If `vp` lands in a folder that isn't on your `PATH` (often `~/.local/bin`), the linking step says so and prints the
line to add. For zsh, the macOS default shell:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
exec zsh
```

`vp` is never written over another program. If something else called `vp` or `voicepipes` is already in the
target folder, it is left alone and the installer stops with an error after installing the app; run it again with
`--bin-dir <another folder>`.

## The first launch: two permissions only you can grant

macOS doesn't let a script grant Microphone or Accessibility access, so on the first launch Voice Pipes opens
**Set up Voice Pipes** and asks for them one at a time:

- **Microphone**: records while you hold or toggle a hotkey, and for `vp listen`, `vp ask` and microphone tracks.
- **Accessibility**: pastes at your cursor and reads the selected text.

**Open Settings…** opens the right Privacy & Security page with a small helper beside it. If Voice Pipes isn't in
the Accessibility list, drag the helper's icon into the list, then switch it on. The same window then downloads the
on-device models in the background and offers the optional OpenRouter and TypeSafe keys
([what needs a key](/setup#what-needs-a-key)).

Check where things stand from a terminal:

```sh
vp status
```

It lists both permissions, the on-device models, which keys are set (masked) and any problems. Without the app
running it only reports the config; any command that needs the app starts it.

## Link vp to an app you already have

If you installed from the DMG, either:

- In the app: **Open Voice Pipes… → Setup → Command line and agents → Install command-line tool**. It links `vp`
  into `/usr/local/bin` (macOS asks for your password once) or, if you decline, `~/.local/bin`, and installs the
  agent skill. The same step is in the first-run window.
- Or from a terminal, without a password, by running the app's binary with `--cli`:

```sh
"/Applications/Voice Pipes.app/Contents/MacOS/VoiceTools" --cli install
vp agents install
```

`vp install` links into `/usr/local/bin` when it is writable, else `~/.local/bin`; `--dir <path>` picks another
folder. It prints the links it made, the binary they point at, and `on_path: true` or `false`.

## Check that it works

```sh
vp --version
vp
```

`vp` on its own prints live state: whether the app is running, the config's health, your tracks and what to run
next. The [CLI reference](/docs/cli) has every command.

## Updates

The app updates itself: it checks for a new version every 5 minutes, and when one is out the menu bar panel offers
**Install…**. `vp update` checks now. Because `vp` is a link to the app's binary, it is updated with the app, and
the app refreshes any installed agent skill when it starts. Permissions carry over between versions.

To reinstall or repair, run the one-line installer again.

## Uninstall

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash -s -- --uninstall
```

It quits the app, removes the agent skill (and the Claude Code session hook, if you added it), removes the `vp` and
`voicepipes` links that point into that copy of the app, and deletes the app. Pass `--apps-dir` if the app is
somewhere other than `/Applications` or `~/Applications`. A link in a folder you can't write to is reported with the
`sudo rm` line to remove it yourself.

It keeps your data: `~/.config/voice-pipes` (config and vocabulary), `~/Library/Application Support/VoiceTools`
(history) and your keys in the Keychain.
