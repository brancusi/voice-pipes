---
title: "Why I built Voice Pipes"
description: "One button and one pipeline weren't enough. I wanted a fast local path and a careful one, a voice that reads back, my own logic anywhere in the pipe, no subscription, and a tool my agents can drive."
date: 2026-10-02
---

Voice is turning into one of the most powerful ways to control a computer, and more and more of what I do runs
through agents. Yet the dictation tools I tried all looked the same: one button, one pipeline, one way of working,
a monthly bill, and my voice sent to someone else's server. Voice Pipes is the tool I wanted instead. Here's why.

## One hotkey isn't enough

Hold-to-talk is perfect for a quick line. It's miserable for a long passage: three minutes of thinking out loud
with a finger pinned to a key. Sometimes I want to tap once, talk for as long as I need, and tap again.

So in Voice Pipes a pipeline (a **track**) can have as many hotkeys as you like, and each one is either **hold**
(records while held) or **toggle** (press to start, press again to stop). Same pipeline, different trigger for the
moment you're in.

<figure class="fig" data-flow>
<div class="card fig__frame">
<div class="fig__row"><span class="sq" style="background: var(--orange)"></span><span class="fig__label">Fast dictation</span><span class="key">⌥Space hold</span><span class="key">⌥⇧D toggle</span></div>
<div class="fig__lane">
<div class="fig__lane-title">Hold <span class="key">⌥Space</span><span class="c-muted">a quick line</span></div>
<div class="fig__row"><span class="hud" data-step="1"><span class="sq" style="background: var(--red)"></span>REC <span class="c-muted">00:02</span></span><span class="sep" data-step="2">›</span><span class="c-muted" data-step="2">let go</span><span class="sep" data-step="2">›</span><span class="hud" data-step="2"><span class="sq" style="background: var(--green)"></span>OK <span class="c-muted">96ms</span></span></div>
<p class="fig__said" data-step="2">“Ship it after lunch.”</p>
</div>
<div class="fig__lane">
<div class="fig__lane-title">Tap <span class="key">⌥⇧D</span><span class="c-muted">a long passage, hands free</span></div>
<div class="fig__row"><span class="hud" data-step="3"><span class="sq" style="background: var(--red)"></span>REC <span class="c-muted">02:41</span></span><span class="sep" data-step="4">›</span><span class="c-muted" data-step="4">tap again</span><span class="sep" data-step="4">›</span><span class="hud" data-step="4"><span class="sq" style="background: var(--green)"></span>OK <span class="c-muted">131ms</span></span></div>
<p class="fig__said fig__said--long" data-step="4">“So here's the plan for the quarter. First, we move the release checks into the pipeline, then…”</p>
</div>
<div class="fig__controls" data-flow-controls hidden><button type="button" class="chip" data-flow-pause aria-pressed="false">Pause</button><button type="button" class="chip" data-flow-replay>Replay</button></div>
</div>
<figcaption>Illustrative recreation of the HUD, not a screenshot: one track with a hold hotkey and a second, toggle hotkey you could add. Text and timings are made up.</figcaption>
</figure>

In the config file, that's one setting on the track:

```toml
hotkeys = [
  { keys = "option+space", mode = "hold" },
  { keys = "option+shift+d", mode = "toggle" },
]
```

## Two speeds, on purpose

Not all dictation is the same job. When I'm drafting an email, I don't mind waiting a moment longer if what lands
is clean, so I'm not running it through Grammarly or re-editing it afterwards. When I'm firing off quick notes or
talking to a terminal, I'm trying to stay in flow, and any lag pulls me out of it.

So the pipelines are yours to shape. The fast one runs Parakeet on the Mac: no network, nothing to wait on. In the
measurements behind the defaults it finished 43 to 140 ms after the recording ended, for 4 to 33 seconds of speech
(on an M5 Max). The careful one sends the audio to a cloud transcription model and then to a language model for
cleanup, through your own OpenRouter key. It takes longer, and for an email that's a fair trade.

<figure class="fig">
<div class="fig__g2">
<div class="card fig__frame">
<div class="fig__row"><span class="sq" style="background: var(--orange)"></span><span class="fig__label">Fast dictation</span><span class="key">⌥Space hold</span></div>
<div class="chain"><span class="c-muted">Mic</span><span class="sep">›</span><span class="c-cyan">Parakeet</span><span class="sep">›</span><span class="c-purple">Fix words</span><span class="sep">›</span><span class="c-green">Paste</span></div>
<p class="fig__note"><span class="fig__tag c-green">ON THIS MAC</span> · works offline once the model is downloaded · 43–140 ms from release to text in our tests</p>
</div>
<div class="card fig__frame">
<div class="fig__row"><span class="sq" style="background: var(--cyan)"></span><span class="fig__label">Clean dictation</span><span class="key">⌥⇧Space toggle</span></div>
<div class="chain"><span class="c-muted">Mic</span><span class="sep">›</span><span class="c-cyan">MAI-Transcribe-2</span><span class="sep">›</span><span class="c-purple">Fix words</span><span class="sep">›</span><span class="c-purple">Claude Haiku cleanup</span><span class="sep">›</span><span class="c-green">Paste</span></div>
<p class="fig__note"><span class="fig__tag c-yellow">CLOUD</span> · two model calls through your OpenRouter key · slower, and polished</p>
</div>
</div>
<figcaption>The two dictation tracks Voice Pipes starts with. Every block can be swapped for another.</figcaption>
</figure>

## Local first, because I'm often offline

I travel a lot, and I'm often on bad hotel Wi-Fi or none at all. I need dictation that works anyway. I also don't
want all my voice data going up to the cloud when there's no reason for it: for everyday dictation, a model on my
own machine is faster.

So the fast path stays on the Mac. Parakeet for transcription and the Pocket TTS and Supertonic voices download
once, the first time you use them, and then run with no connection. Fix words and History never leave the Mac
either. The cloud is there for when I want something special, a bigger model or a web search, and only in the
blocks I choose, with my own keys.

## Speaking and listening belong together

Talking to my computer and having it talk back are the same idea, so why were they always two different tools?
Voice Pipes reads to you, too: select text, press a key, and a voice on your Mac reads it. Press the same key to
pause and again to carry on.

The same goes for agents. An agent can speak to me when a long job finishes, or ask me a question out loud and use
my spoken answer, without me ever looking at the screen.

<figure class="fig">
<div class="fig__g2">
<div class="card fig__frame">
<div class="fig__row"><span class="sq" style="background: var(--purple)"></span><span class="fig__label">Read aloud</span><span class="key">⌥R toggle</span></div>
<div class="chain"><span class="c-muted">Selection</span><span class="sep">›</span><span class="c-green">Speak · Pocket TTS</span></div>
<div class="fig__row"><span class="hud"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">42%</span></span><span class="key">⏸</span><span class="key">⏹</span></div>
</div>
<div class="card fig__frame">
<div class="fig__label">An agent, from the terminal</div>
<pre class="fig__term" tabindex="0"><span><span class="c-muted">$</span> vp say "Tests passed."</span><span><span class="c-muted">$</span> vp ask "Deploy now or after review?"</span><span class="c-muted">question: Deploy now or after review?</span><span>answer: after review</span></pre>
</div>
</div>
<figcaption>Illustrative recreation, not a screenshot or a real run: the read-aloud HUD, and an agent speaking and asking with <code>vp</code>.</figcaption>
</figure>

## A tool you own

I'm tired of subscriptions for everything. I like the old model: you get a tool, you own it, and it keeps working
perfectly well until a new version is worth having. That's the spirit Voice Pipes is built in. There's no account
to sign up for, the fast path needs nothing but your Mac, and when you do use cloud models you bring your own keys,
so you pay those providers for what you use and nothing more.

## My logic, anywhere in the pipe

The thing I missed most was a way to add my own step. I keep notes and dictations in my own system, and I want
every take sent there too, without a second tool. In Voice Pipes that's just one more block: an HTTP request to
your endpoint, anywhere in the pipeline. Output blocks pass their text on, so a track can paste at the cursor *and*
post to your notes.

<figure class="fig">
<div class="card fig__frame">
<div class="fig__row"><span class="sq" style="background: var(--yellow)"></span><span class="fig__label">Voice note</span><span class="key">⌥N toggle</span></div>
<div class="chain"><span class="c-muted">Mic</span><span class="sep">›</span><span class="c-cyan">Parakeet</span><span class="sep">›</span><span class="c-purple">Fix words</span><span class="sep">›</span><span class="c-green">Paste</span><span class="sep">›</span><span class="c-green">HTTP POST</span><span class="c-muted">→ your notes service</span></div>
</div>
<figcaption>A track you could build: dictation that also lands in your own notes. The token stays in the Keychain, not the file.</figcaption>
</figure>

```toml
  [[track.step]]
  type = "http"
  method = "POST"
  url = "https://notes.example.com/api/notes"
  headers = { Authorization = "Bearer ${secret:notes}", "Content-Type" = "application/json" }
  body = '{"text": {{input_json}}}'
```

## Agent-first, all the way down

If voice is going to be a control surface for agentic work, the tool has to be one an agent can use and configure.
So everything (your tracks, their blocks, their hotkeys, your settings) lives in one TOML file,
`~/.config/voice-pipes/config.toml`, with a schema and a checker. And there's `vp`, the command line. With it an
agent can run your tracks, speak to you, ask you something, transcribe a file without rolling its own speech
pipeline, edit your vocabulary, read your history, and open any window in the app to show you what it's doing.

Most of all, I want the agent to build pipelines for me. Describe the track you want; it edits the config, checks
it, and you watch each block appear in the editor as it's added.

<figure class="fig" data-flow>
<div class="card fig__frame">
<div class="fig__g2">
<pre class="fig__term" tabindex="0"><span data-step="1"><span class="c-muted"># the agent adds [[track]] voice-note</span></span><span data-step="1"><span class="c-muted">$</span> vp config check</span><span data-step="1" class="c-green">result: ok</span><span data-step="2"><span class="c-muted">$</span> vp open track voice-note</span><span data-step="3"><span class="c-muted"># + transcribe, fix-words</span></span><span data-step="5"><span class="c-muted"># + http (POST to your notes)</span></span><span data-step="6"><span class="c-muted">$</span> vp run voice-note --text "…"</span></pre>
<div class="fig__editor" data-step="2">
<div class="fig__row"><span class="sq" style="background: var(--yellow)"></span><span class="fig__label">Voice note</span><span class="key">⌥N toggle</span></div>
<div class="fig__block" style="--accent: var(--fg-muted)"><span class="fig__n">1</span>Microphone</div>
<div class="fig__block" style="--accent: var(--cyan)" data-step="3"><span class="fig__n">2</span>Transcribe <span class="c-muted">Parakeet · on this Mac</span></div>
<div class="fig__block" style="--accent: var(--purple)" data-step="4"><span class="fig__n">3</span>Fix words</div>
<div class="fig__block" style="--accent: var(--green)" data-step="5"><span class="fig__n">4</span>HTTP request <span class="c-muted">POST</span></div>
<div class="fig__row" data-step="6"><span class="hud"><span class="sq" style="background: var(--green)"></span>OK <span class="c-muted">212ms</span></span></div>
</div>
</div>
<div class="fig__controls" data-flow-controls hidden><button type="button" class="chip" data-flow-pause aria-pressed="false">Pause</button><button type="button" class="chip" data-flow-replay>Replay</button></div>
</div>
<figcaption>Illustrative recreation, not a screenshot or a real run: an agent building a track while the editor shows each new block. Timings are made up.</figcaption>
</figure>

One line installs the app, `vp` and a skill that teaches Claude Code, Codex and other agents to use it:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

macOS still asks you, not the script, for Microphone and Accessibility the first time. The
[install guide](/docs/install), the [CLI reference](/docs/cli) and [agents](/docs/agents) pages have the rest.

## The word it keeps getting wrong

Every dictation tool has a word it can't get right. For me it was my own surname. It's a small thing, but it
happens every single time, and it's usually what pushes people to run every dictation through an LLM cleanup:
slower, costlier and sometimes too clever, all to fix one word.

Voice Pipes fixes it the simple way. **Fix words** is a find-and-replace list, applied on your Mac in effectively no
time: whenever transcription writes one of the "heard as" versions, you get the spelling you want. (I also tried
boosting the speech model's vocabulary instead. It was slower, and it started putting my terms where they didn't
belong.)

The hard part is knowing every way a word gets misheard, so you train it with **takes**. Say the word about five
times; each take is replayed about 30 ways (faster, slower, quieter, noisier) through Parakeet, and you get every
distinct way it came out. Then Jev, one of the new "System One" decision models from TypeSafe, judges each one: is
this a garbled version of your word, safe to replace everywhere, or a real word you'd want left alone? When I tested
it on my own name (with macOS voices standing in for me), five takes became 150 variations in about five seconds,
and Parakeet got the name right only 4 times. To be clear about what this is: it doesn't retrain the speech model,
it learns how the model mishears you and fixes those spellings.

<figure class="fig" data-flow>
<div class="card fig__frame">
<div class="fig__row"><span class="fig__label">Train “Kubernetes”</span><span class="key" data-step="1">take 1</span><span class="key" data-step="1">take 2</span><span class="key" data-step="1">take 3</span><span class="key" data-step="1">take 4</span><span class="key" data-step="1">take 5</span></div>
<p class="fig__note" data-step="2">150 variations through Parakeet · right 6 times · Jev judges each result</p>
<div class="fig__result" data-step="3"><span class="fig__box fig__box--on">✓</span><span>cube or netties</span><span class="c-muted">41×</span><span class="c-green">91%</span></div>
<div class="fig__result" data-step="3"><span class="fig__box fig__box--on">✓</span><span>cuban eighties</span><span class="c-muted">23×</span><span class="c-green">84%</span></div>
<div class="fig__result" data-step="3"><span class="fig__box fig__box--on">✓</span><span>cooper nettys</span><span class="c-muted">9×</span><span class="c-green">72%</span></div>
<div class="fig__result" data-step="3"><span class="fig__box"></span><span>cuban</span><span class="c-muted">4×</span><span class="c-muted">8%</span></div>
<div class="fig__row" data-step="4"><span class="c-green">Added to Heard as:</span><span>Kubernetes ← cube or netties, cuban eighties, cooper nettys</span></div>
<div class="fig__controls" data-flow-controls hidden><button type="button" class="chip" data-flow-pause aria-pressed="false">Pause</button><button type="button" class="chip" data-flow-replay>Replay</button></div>
</div>
<figcaption>Illustrative recreation, not a screenshot: training a word from five takes. The results and Jev's scores are made up; a real word like “cuban” scores low and stays unticked.</figcaption>
</figure>

Jev runs in the cloud with your TypeSafe key; without one, Voice Pipes ticks the likely mishearings with a simpler
rule, and everything else in training stays on your Mac. Agents can help here too: `vp vocab add` and
`vp vocab test` let one build up the list for you, and the takes are yours to give.

## What it adds up to

A voice tool that bends to the job instead of the other way round: two speeds, hands-free when you need it, a voice
that reads back, your own steps anywhere in the pipe, local first, no subscription, and all of it open to your
agents. That's Voice Pipes. [Download it](https://github.com/brancusi/voice-tools-releases/releases/latest/download/Voice-Pipes.dmg),
or install it from a terminal with the line above.
