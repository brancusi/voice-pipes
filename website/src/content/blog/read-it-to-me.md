---
title: "Read it to me"
description: "I wanted my agent to speak up when it has something worth hearing, not on every reply, and to show me the words as it reads, so I can jump around, change the speed and stop when I've heard enough. Here's how Voice Pipes does it, through one command line."
date: 2026-10-02T15:00:00Z
---

My agents write me a lot. At the end of a long job I get a summary: what changed, what broke, what needs my call.
Half the time I'm not looking at the screen when it lands, and the other half I'd rather lean back and listen than
read another wall of text. What I always wanted was simple to say and hard to build: an agent that speaks to me
when it has something worth hearing, and a spoken summary I can steer. Jump to the part I care about, speed it up,
slow it down, and stop when I've heard enough.

Voice Pipes can do that now. This is how it works, and why it runs through the command line.

## Not every reply deserves a voice

The obvious version is a plugin that reads every reply out loud. I didn't want that. Half of what an agent says is
"Done." or "Renamed the variable in two files." Read all of that aloud and within the hour you're hunting for the
mute switch, and then the voice is off when something important comes along.

But length isn't the rule either. "Tests failed on main" is four words, and I want to hear it right now. A long
summary I asked for is worth hearing; a long log dump nobody asked for isn't. The real question is whether hearing
it adds something at this moment. That's a judgement call, and I didn't want it buried inside a trigger that fires
on every turn.

<figure class="fig" data-flow>
<div class="card fig__frame">
<div class="fig__label">Three replies, three different calls</div>
<div class="fig__lane">
<div class="fig__row"><span class="fig__tag c-muted">REPLY</span><span class="fig__said">“Renamed userId to accountId in two files.”</span></div>
<div class="fig__row" data-step="2"><span class="sep">›</span><span class="key">stays on screen</span><span class="c-muted">nothing to hear</span></div>
</div>
<div class="fig__lane">
<div class="fig__row"><span class="fig__tag c-muted">REPLY</span><span class="fig__said">“Tests failed on main: three in auth.”</span></div>
<div class="fig__row" data-step="2"><span class="sep">›</span><span class="key">worth hearing now</span><span class="c-muted">short, and it matters</span></div>
<pre class="fig__term" tabindex="0" data-step="3"><span><span class="c-muted">$</span> vp say "Tests failed on main. Three in auth."</span></pre>
<div class="fig__row" data-step="4"><span class="hud"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">60%</span></span></div>
</div>
<div class="fig__lane">
<div class="fig__row"><span class="fig__tag c-muted">REPLY</span><span class="fig__said fig__said--long">“Here's what changed in the session store. Three things…” (six sentences)</span></div>
<div class="fig__row" data-step="2"><span class="sep">›</span><span class="key">you asked: read it to me</span><span class="c-muted">long, and wanted</span></div>
<pre class="fig__term" tabindex="0" data-step="3"><span><span class="c-muted">$</span> vp open reading</span><span><span class="c-muted">$</span> printf '%s' "$SUMMARY" | vp say</span></pre>
<div class="fig__stack" data-step="4"><span class="fig__mini" aria-hidden="true"><span class="fig__mini-line"></span><span class="fig__mini-line fig__mini-line--now"></span><span class="fig__mini-line"></span></span><span class="hud"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">14%</span></span></div>
</div>
<div class="fig__controls" data-flow-controls hidden><button type="button" class="chip" data-flow-pause aria-pressed="false">Pause</button><button type="button" class="chip" data-flow-replay>Replay</button></div>
</div>
<figcaption>Illustrative recreation with made-up text, not a screenshot or a real run: the agent (or you) decides whether a reply is worth hearing; <code>vp</code> hands the text to the Voice Pipes app, which speaks it and shows the HUD at the bottom of the screen.</figcaption>
</figure>

## Hear it and see it

The other half of the idea is reading along. When a long summary is read to me, I want the words in front of me at
the same time: if I drift for a sentence, I glance back; if the next paragraph is the one I care about, I go
straight there.

So while anything is read aloud, the HUD (the small tag at the bottom of the screen) has a button that opens a card
above it with the whole text, one sentence per line. The sentence being read is lit with a lavender bar, the ones
already read dim, and a thin underline runs along under the word being spoken. It's exact with macOS voices and
closely estimated with the others. The card scrolls with the voice; hold the pointer over it to look ahead, and it
follows the voice again when you move away.

And it's mine to steer:

- **Click any sentence** and reading carries on from there, with any voice. Skip ahead to the part I care about, or
  go back over something I missed.
- **− and +** change the speed on the spot, from 0.6× to 2×, for that reading only. The track's own speed stays as
  set.
- **Pause and stop** are on the tag, as they always were. Stop means stop: I've heard enough.

The card stays open for the next reading until I close it.

<figure class="fig" data-flow data-stage="5">
<div class="card fig__frame">
<div class="ra" aria-hidden="true">
<div class="ra__card">
<div class="ra__text">
<p class="ra__s" data-cur="0" data-done="1 2 3 4 5">I <span data-ul="0">refactored</span> the session store, and the tests pass.</p>
<p class="ra__s" data-cur="1" data-done="2 3 4 5">There are three things to <span data-ul="1">know.</span></p>
<p class="ra__s ra__s--para" data-cur="2" data-done="3 4 5">First, sessions now expire after a day <span data-ul="2">instead</span> of a week.</p>
<p class="ra__s" data-done="3 4 5">Second, the login page reads the new expiry, so nobody signed in today gets logged out.</p>
<p class="ra__s" data-cur="3 4" data-hov="2">Third, I removed the old cookie <span data-ul="3">helper,</span> since nothing else <span data-ul="4">used</span> it.</p>
<p class="ra__s ra__s--para" data-cur="5">One thing needs your call: should the <span data-ul="5">expiry</span> be a setting?</p>
</div>
<div class="ra__foot"><span class="ra__voice" data-on="0 1 3 4 5">Alba · Pocket TTS</span><span class="ra__voice" data-on="2">click a sentence to read from there</span><span class="ra__btn">−</span><span class="ra__rate" data-on="0 1 2 3">1.0×</span><span class="ra__rate" data-on="4 5">1.3×</span><span class="ra__btn" data-lit="4">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted" data-on="0">4%</span><span class="c-muted" data-on="1">17%</span><span class="c-muted" data-on="2">31%</span><span class="c-muted" data-on="3">58%</span><span class="c-muted" data-on="4">66%</span><span class="c-muted" data-on="5">83%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span></div>
</div>
<ul class="ra__keys">
<li data-lit="2 3"><span class="key">click a sentence</span> jump there; reading carries on</li>
<li data-lit="4"><span class="key">− +</span> speed, 0.6× to 2×, live</li>
<li><span class="key"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span> pause, or stop when you've heard enough</li>
</ul>
<div class="fig__controls" data-flow-controls hidden><button type="button" class="chip" data-flow-pause aria-pressed="false">Pause</button><button type="button" class="chip" data-flow-replay>Replay</button></div>
</div>
<figcaption>Illustrative recreation of the read-along card and the HUD tag, not a screenshot: the text is made up and nothing here plays sound or controls the app. It reads, jumps ahead to the fifth sentence, then speeds up to 1.3×.</figcaption>
</figure>

## One engine, many front doors

Voice Pipes already knew how to read aloud. It has the voices (Pocket TTS and Supertonic on the Mac, the macOS
voices, and OpenRouter's speech models with your own key), it pauses and resumes, it shows the HUD, and now it has
the read-along card. I didn't want a second copy of all that inside every agent harness, each with its own voice
settings, its own bugs and its own idea of what "pause" means. I wanted one engine and a simple way in.

That way in is `vp`, the command line. Everything is going command-line again, and for good reason: a CLI is the one
interface every agent already speaks. Any harness that can run a shell command can use it, with no SDK and no
plugin per tool. It composes with pipes. It answers in compact text an agent can read, with exit codes and a hint
when something goes wrong. And the logic stays in one place: when the app gets better at reading aloud, every agent
that calls `vp` gets better with it.

Reading a summary to me takes two commands:

```sh
vp open reading
printf '%s' "$SUMMARY" | vp say
```

`vp open reading` opens the card for this reading and the next ones. `vp say` reads exactly the text it's given and
returns when the reading ends, whether it finished, I stopped it, or I jumped around on the way. It doesn't
summarise anything: the agent writes the summary, and Voice Pipes reads it. The agent can steer too, from another
shell:

```sh
vp speed 1.4
vp pause
vp resume
vp stop
vp close reading
```

The default voice is Pocket TTS, on the Mac: it downloads once, the first time, and then reads with no connection.
The macOS voices are on the Mac as well. An OpenRouter voice needs the network and your key, and you pay OpenRouter for
it.

## Two ways to plug it in

There are two honest ways to wire this into an agent, and they're good at different things.

**Let the model decide.** Installing `vp` also installs a skill for Claude Code, Codex and other agents that read
skills. It tells the agent that it can talk to you (`vp say`), ask you something out loud (`vp ask`), and read long
text to you in the HUD. When you say "read me the summary", it writes the summary for listening, opens the card,
pipes the text to `vp say`, and waits until the reading ends before it says anything else. The judgement lives with
the model, which has the context: it knows whether you asked, whether it's the end of a long job, and whether the
reply is worth your ears.

**Or drive it mechanically.** Most harnesses let you run a command on an event: a hook, an extension, a script that
fires when a job ends. That's deterministic, which is exactly what you want for a rule you never want broken. Keep
the trigger simple and explicit, and keep the judgement out of it. Voice Pipes doesn't ship a hook that speaks (the
only one it installs, for Claude Code, prints a line of Voice Pipes state when a session starts), so this part is
yours. A sketch of the speaking end, for whatever your harness hands it:

```sh
# Your own hook; Voice Pipes doesn't install this.
# It reads aloud whatever text it's given on stdin.
text=$(cat)
[ -n "$text" ] || exit 0
vp open reading > /dev/null
printf '%s' "$text" | vp say > /dev/null
```

What text it's handed, and when, is your call: the agent's closing summary, only when a run took more than a few
minutes, only when you've switched it on for the afternoon. If something else is already playing or recording,
`vp say` fails with `busy` and exits 1 rather than talking over it.

<figure class="fig">
<div class="fig__g2">
<div class="card fig__frame">
<div class="fig__row"><span class="fig__label">A hook in your harness</span><span class="fig__tag c-yellow">YOU WRITE THIS</span></div>
<p class="fig__note">Fires on an event you pick. Same event, same result, every time.</p>
<div class="chain"><span class="c-muted">job ends</span><span class="sep">›</span><span class="c-muted">your rule</span><span class="sep">›</span><span class="c-green">vp say</span></div>
</div>
<div class="card fig__frame">
<div class="fig__row"><span class="fig__label">The model decides</span><span class="fig__tag c-green">SHIPS WITH VOICE PIPES</span></div>
<p class="fig__note">The skill teaches when reading helps and how to write for the ear.</p>
<div class="chain"><span class="c-muted">“read me the summary”</span><span class="sep">›</span><span class="c-purple">writes it for listening</span><span class="sep">›</span><span class="c-green">vp open reading · vp say</span></div>
</div>
</div>
<div class="card fig__frame">
<div class="chain"><span class="c-green">vp</span><span class="sep">›</span><span class="fig__label">Voice Pipes app</span><span class="c-muted">voices · HUD · read-along · jump · speed · pause · stop</span></div>
</div>
<figcaption>Two ways in, one engine. The trigger, the judgement about whether speech adds anything, and the speech itself are separate pieces; only the skill and the engine ship with Voice Pipes.</figcaption>
</figure>

## Writing for the ear

One thing I learned quickly: a summary written for the screen sounds terrible read aloud. Markdown, bullets, file
paths and URLs are read out literally. So the skill tells agents to write for listening: plain spoken sentences,
short paragraphs, and "three things" followed by the three things. A new paragraph starts with a gap in the card,
so the shape of it is still there when you look.

It also tells them not to talk over the reading: wait for `vp say` to return before speaking or asking anything
else. You're the one holding the remote.

## Try it

The read-along card and live speed arrived in 1.6.4; jumping to a sentence and the running word cursor in 1.6.5.
If you already have Voice Pipes, update from the menu bar panel and the skill updates with it. If you don't, one
line installs the app, `vp` and the skill:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

Then finish a long job with your agent and say "read me the summary". The [agents guide](/docs/agents) has the
details and patterns, the [CLI reference](/docs/cli#vp-speed) every reading command, and [install](/docs/install)
the rest.
