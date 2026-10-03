---
title: "Reading aloud"
nav: "Reading aloud"
description: "Follow and steer anything Voice Pipes reads aloud: the read-along card, jumping between sentences, live speed, the HUD's keys and when it takes them, shortcuts, and the same controls from vp and config.toml. Matches Voice Pipes 1.8.1."
order: 4
---

Voice Pipes reads aloud for the Read aloud track (⌥R, toggle), any track that ends in Speak, `vp say`, the question
in `vp ask`, and agents that use it. Every reading works the same way: the HUD at the bottom of the screen shows it,
and you can follow the text, jump around, change the speed and stop, with the mouse, the keyboard or `vp`. Nothing
here brings Voice Pipes to the front: the app you're in stays active.

This page matches Voice Pipes **1.8.1**.

## Follow along

While anything is read aloud, the HUD's ☰ button opens the **read-along card** above it: the whole text, a sentence
per line, with the one being read lit and a thin underline running under the word being spoken (exact with macOS
voices, closely estimated with the others). The card scrolls with the voice; hold the pointer over it to look ahead,
and it follows the voice again when the pointer leaves.

- **Click a sentence** to carry on reading from there, with any voice.
- **− and +** change the speed on the spot, from 0.6× to 2×, for this reading only. The track's own speed stays as
  set.
- **Pause and stop** are the HUD's buttons. Pressing the track's hotkey again also pauses and resumes.

The card stays open for later readings until you close it (˅). From a terminal, `vp open reading` shows it and
`vp close reading` hides it.

## Keys while reading

The HUD can take the keyboard while something is read, without bringing Voice Pipes forward. While it has the keys,
**KEYS ON** shows in the HUD, and these work:

| Key | Does |
| --- | --- |
| Esc | Stop |
| Space | Pause, or resume |
| j or ↓ | Next sentence |
| k or ↑ | Previous sentence |
| h or − | Slower (0.1× a press) |
| l or = | Faster (0.1× a press) |
| g | Back to the start |
| G (⇧G) | The last sentence |

Other keys do nothing while the HUD has the keyboard, so they don't land in your app by mistake. A ⌘ shortcut gives
the keys straight back to your app, and so does clicking it.

### When the HUD takes the keys

**Setup → Reading → Keyboard while reading**, or `take_keys` in config.toml:

| Setting | `take_keys` | The HUD's keys work |
| --- | --- | --- |
| Always (the default since 1.8.1) | `always` | As soon as something starts being read. Click your app to type again |
| Point or click | `hover` | When you move the pointer onto the HUD or click it; move away and the keys are yours again. A HUD that appears under a resting pointer doesn't count |
| Click | `click` | When you click the HUD; click anywhere else to give them back |
| Never | `never` | Only the HUD's buttons, and any shortcuts you add below |

**When I click away** (`click_away`) decides what clicking another app does while the HUD has the keys: **Keep
reading** (the default, `keep-reading`) or **Stop** (`stop`).

### Change the keys

Each action can have any keys you like: in **Setup → Reading → Keys while the HUD has the keyboard** (each key is a
chip with its ×; **Reset to defaults** puts back Esc, Space, j/k, h/l, g/G), in config.toml, or with `vp reading key`.
Plain keys are fine here: they only work while the HUD has the keyboard.

### Shortcuts that work in any app

**Anywhere while reading → + Add shortcut** adds a shortcut for an action that works in whatever app you're in, but
only while something is being read, say ⌃⌥→ for faster. None are set until you add one. Include ⌃, ⌥ or ⌘ so it
doesn't take a key away from your typing while a reading plays.

## The same from a terminal

```sh
# Steer what's playing (next, prev and speed never start the app)
vp next
vp prev
vp speed 1.4
vp pause
vp resume
vp stop

# How readings are steered from the keyboard
vp reading
vp reading keys hover
vp reading click-away stop
vp reading key faster period shift+equal
vp reading shortcut faster control+option+right
vp reading reset
```

`vp reading` edits `[settings.reading]` in config.toml, so it works with the app closed. The [CLI
reference](/docs/cli#vp-reading) has every form and its output; [config.toml](/docs/config#settings) has the
settings with their defaults.

You can also ask an agent that has the [skill](/docs/agents): "don't take my keys" sets `hover` (or `click` or
`never`, as you prefer), "always take them" sets `always`. The skill tells agents to change these only when you ask.

## Hard text

Plain prose reads well as it is, but "$4.2M", a file path or a table doesn't. The starter Read aloud on new installs
(since 1.7.0) starts with a [Branch](/docs/config#branch-one-track-several-paths): Jev judges how hard the text is
to read aloud, and figures, code, paths, URLs and tables are rewritten into sentences you can follow by ear before
the voice reads them. That needs a Jev key and an OpenRouter key ([what needs a key](/setup#what-needs-a-key));
without them, the text is read as it is. An update doesn't change a Read aloud you already have; add the Branch
block yourself, or ask your agent to.

## For agents

Agents read to you through the same HUD: `vp open reading`, then `printf '%s' "$TEXT" | vp say`, which returns
when the reading ends. What they read without being asked is your choice, saved once for every agent: see
[what agents read aloud](/docs/agents#what-agents-read-aloud).
