---
title: "Treat audio like a page"
description: "When I read along while something is read to me, I want to move through the voice the way my eyes move through a page: skim what I know, slow down for the hard part, go back and hear it again. Here's how the read-along keys in Voice Pipes let me do that."
date: 2026-10-03T09:00:00Z
---

Give me a page and I never read it straight through at one speed. My eyes skim the paragraph I already know, slow
down on the sentence that carries the idea, jump back two lines when something didn't land, and glance ahead to see
where it's going. Nobody taught me that. It's just what reading is.

Listening has always felt different to me. A voice reads at its pace, in its order, from the first word to the last.
If a sentence slipped past, getting it back meant scrubbing a timeline and hoping. So I kept having to choose: read
it myself, or sit back and let it wash over me.

What I actually want is both at once, with the voice as easy to steer as my eyes.

## Two senses, one pace

I like reading and listening at the same time. With the words in front of me and a voice in my ear, I drift less,
and more of it stays with me. That's my experience, not a law of learning; plenty of people prefer one or the other,
and that's fine.

But the moment I do both, the voice's pace becomes the problem. Text isn't evenly dense. The setup paragraph of an
idea I've met a dozen times goes by too slowly; the one sentence that does the real work goes by too fast. How
quickly I can take something in depends on what it says and on what I already know, and both change from sentence
to sentence.

A page lets me match my pace to the text at every moment, and going back costs nothing. That's what I wanted from
audio: not one speed for the whole thing, but steering as cheap as moving my eyes. Fast where it's familiar, slow
where it's dense, and a replay that takes one key, not a hunt.

## The page, in the HUD

In [Read it to me](/blog/read-it-to-me) I wrote about the read-along card: while anything is read aloud, the HUD at
the bottom of the screen can open a card above it with the whole text, one sentence per line. That's the page. The
sentence being read has a lavender bar, the ones already read are dimmed, and a thin underline runs under the word
being spoken (exact with the macOS voices, closely estimated with the others).

What's new since then is that my hands can steer it without reaching for the mouse. When the HUD has the keyboard,
it says so: **KEYS ON** at the foot of the card, with the keys, and a small **KEYS** mark on the tag.

<figure class="fig">
<div class="card fig__frame">
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s" data-done="0">A Bloom filter answers one question: have I seen this before?</p>
<p class="ra__s" data-done="0">It's a row of bits, all zero to start, and a few hash functions.</p>
<p class="ra__s" data-done="0">To add an item, run it through each function and set the bits they point to.</p>
<p class="ra__s" data-cur="0">To check an item, look at the same bits: if any is <span data-ul="0">zero,</span><span class="rk-ahead"> it was never added; if all are set, it probably was.</span></p>
<p class="ra__s ra__s--para">That “probably” is the whole trick.</p>
<p class="ra__s">A filter can be wrong about yes but never about no, and a longer row makes it wrong less often.</p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">1.0×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">51%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<ul class="ra__keys rk-legend">
<li><span class="rk-sw" aria-hidden="true"></span>the sentence being read</li>
<li><span class="rk-ul">word</span>the word being spoken</li>
<li><span class="rk-on">KEYS ON</span>the HUD has your keys, and lists them</li>
<li><span class="key">− 1.0× +</span>this reading's speed</li>
</ul>
</div>
<figcaption>Illustrative recreation of the read-along card and the HUD tag as they look in Voice Pipes 1.8.1, not a screenshot. The text is made up and nothing here plays sound.</figcaption>
</figure>

## The keys

The defaults are Vim's, because that's where my fingers already rest, with the arrows and minus and equals for
everyone else:

| Key | Or | What it does |
| --- | --- | --- |
| <kbd class="key">Space</kbd> | | Pause / resume |
| <kbd class="key">j</kbd> | <kbd class="key">↓</kbd> | Next sentence |
| <kbd class="key">k</kbd> | <kbd class="key">↑</kbd> | Previous sentence |
| <kbd class="key">h</kbd> | <kbd class="key">−</kbd> | Slower, by 0.1× a press |
| <kbd class="key">l</kbd> | <kbd class="key">=</kbd> | Faster, by 0.1× a press |
| <kbd class="key">g</kbd> | | Back to the start |
| <kbd class="key">⇧G</kbd> | | Last sentence |
| <kbd class="key">Esc</kbd> | | Stop and close |

A few things worth knowing, because they're how it actually behaves:

- **The step is a sentence.** I think of text in blocks, but the app thinks in sentences: <kbd>j</kbd> and
  <kbd>k</kbd> move exactly one, the same lines the card shows. A paragraph shows up as a gap in the card, but there's
  no paragraph jump. To skip a paragraph, press <kbd>j</kbd> a few times, or click the sentence you want.
- **<kbd>k</kbd> goes to the start of the sentence before the one being read.** So when the voice has just moved on
  and the last sentence didn't land, one <kbd>k</kbd> brings it back. To hear the sentence you're in from its start,
  press <kbd>k</kbd> then <kbd>j</kbd>.
- **A jump always carries on reading**, even from a pause. At the ends, <kbd>j</kbd> on the last sentence starts it
  again, and so does <kbd>k</kbd> on the first.
- **Speed runs from 0.6× to 2×**, in tenths, and only for this reading; the track keeps its own speed for next time.
- **<kbd>Space</kbd> pauses and resumes** from the same spot. While the voice is still loading, before the first
  sound, there's nothing to pause yet.
- **<kbd>Esc</kbd> stops the reading** and the HUD fades away. If the card was open, it opens again with the next
  reading.

The keys move the voice, not a selection. Nothing in the card gets selected or copied, and the app you started the
reading from never sees these keys.

## One read, scene by scene

Here's how it feels on something I half know. I select a short explainer of Bloom filters in my browser, press
<kbd>⌥R</kbd> (the Read aloud track's default hotkey), and read along with the card open.

<figure class="fig">
<ol class="rk-story">
<li class="card rk-scene">
<div class="rk-scene__head"><span class="rk-n">1</span><span class="fig__label">Reading along</span><span class="key">⌥R</span></div>
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s" data-cur="0">A Bloom filter answers one question: have I <span data-ul="0">seen</span><span class="rk-ahead"> this before?</span></p>
<p class="ra__s">It's a row of bits, all zero to start, and a few hash functions.</p>
<p class="ra__s">To add an item, run it through each function and set the bits they point to.</p>
<p class="ra__s">To check an item, look at the same bits: if any is zero, it was never added; if all are set, it probably was.</p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">1.0×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">8%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<p class="fig__note">The first sentence is lit and the underline follows the voice. The HUD has the keys from the start (KEYS ON), and my browser stays in front.</p>
</li>
<li class="card rk-scene">
<div class="rk-scene__head"><span class="rk-n">2</span><span class="fig__label">I know this part</span><span class="key">l l l</span></div>
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s" data-done="0">A Bloom filter answers one question: have I seen this before?</p>
<p class="ra__s" data-cur="0">It's a row of bits, all <span data-ul="0">zero</span><span class="rk-ahead"> to start, and a few hash functions.</span></p>
<p class="ra__s">To add an item, run it through each function and set the bits they point to.</p>
<p class="ra__s">To check an item, look at the same bits: if any is zero, it was never added; if all are set, it probably was.</p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">1.3×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">17%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<p class="fig__note">Three presses of <kbd>l</kbd>: 1.0× becomes 1.3× while I skim the setup. The sentence already read is dimmed.</p>
</li>
<li class="card rk-scene">
<div class="rk-scene__head"><span class="rk-n">3</span><span class="fig__label">The dense one</span><span class="key">h h h h</span></div>
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s" data-done="0">It's a row of bits, all zero to start, and a few hash functions.</p>
<p class="ra__s" data-done="0">To add an item, run it through each function and set the bits they point to.</p>
<p class="ra__s" data-cur="0">To check an item, look at the same bits: if any is <span data-ul="0">zero,</span><span class="rk-ahead"> it was never added; if all are set, it probably was.</span></p>
<p class="ra__s ra__s--para">That “probably” is the whole trick.</p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">0.9×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">51%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<p class="fig__note">Four presses of <kbd>h</kbd> bring it down to 0.9× for the sentence that does the work.</p>
</li>
<li class="card rk-scene">
<div class="rk-scene__head"><span class="rk-n">4</span><span class="fig__label">Hear it again</span><span class="key">k</span></div>
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s" data-done="0">To add an item, run it through each function and set the bits they point to.</p>
<p class="ra__s" data-cur="0"><span data-ul="0">To</span><span class="rk-ahead"> check an item, look at the same bits: if any is zero, it was never added; if all are set, it probably was.</span></p>
<p class="ra__s ra__s--para">That “probably” is the whole trick.</p>
<p class="ra__s">A filter can be wrong about yes but never about no, and a longer row makes it wrong less often.</p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">0.9×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">41%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<p class="fig__note">The voice had already moved on to “That ‘probably’…”. One <kbd>k</kbd> and it's back at the start of the sentence I wanted again.</p>
</li>
<li class="card rk-scene">
<div class="rk-scene__head"><span class="rk-n">5</span><span class="fig__label">Let it land</span><span class="key">Space</span></div>
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s" data-done="0">To check an item, look at the same bits: if any is zero, it was never added; if all are set, it probably was.</p>
<p class="ra__s ra__s--para" data-cur="0">That “probably” is the whole <span data-ul="0">trick.</span></p>
<p class="ra__s">A filter can be wrong about yes but never about no, and a longer row makes it wrong less often.</p>
<p class="ra__s">So it's a cheap first check before a slow lookup.</p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">0.9×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--fg-muted)"></span>PAUSED <span class="c-muted">69%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M2 1l5 3-5 3z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<p class="fig__note"><kbd>Space</kbd> pauses: the tag says PAUSED and the line stays lit while I think. <kbd>Space</kbd> again carries on from where it stopped.</p>
</li>
<li class="card rk-scene">
<div class="rk-scene__head"><span class="rk-n">6</span><span class="fig__label">Skip ahead</span><span class="key">j j</span></div>
<div class="ra" aria-hidden="true" data-stage="0">
<div class="ra__card">
<div class="ra__text rk-win">
<p class="ra__s ra__s--para" data-done="0">That “probably” is the whole trick.</p>
<p class="ra__s" data-done="0">A filter can be wrong about yes but never about no, and a longer row makes it wrong less often.</p>
<p class="ra__s" data-cur="0">So it's a cheap <span data-ul="0">first</span><span class="rk-ahead"> check before a slow lookup.</span></p>
</div>
<div class="ra__foot"><span class="rk-on">KEYS ON</span><span class="rk-hint"><span>Esc</span> stop · <span>Space</span> pause · <span>J/K</span> sentence · <span>H/L</span> speed</span><span class="ra__btn">−</span><span class="ra__rate">0.9×</span><span class="ra__btn">+</span></div>
</div>
<div class="hud ra__tag"><span class="sq" style="background: var(--purple)"></span>READ <span class="c-muted">93%</span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h2v6H1zM5 1h2v6H5z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 1h6v6H1z" fill="currentColor"/></svg></span><span class="ra__btn"><svg viewBox="0 0 8 8" width="8" height="8"><path d="M1 2.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></span><span class="rk-keys">KEYS</span></div>
</div>
<p class="fig__note">Two presses of <kbd>j</kbd> skip the sentence I already knew and land on the last one. When I've heard enough, <kbd>Esc</kbd> stops and closes the HUD.</p>
</li>
</ol>
<figcaption>Illustrative recreations of the read-along card and HUD tag as of Voice Pipes 1.8.1, with made-up text: not screenshots, and nothing here plays sound. The keys are the defaults; the speeds and percentages are worked out from the sample text.</figcaption>
</figure>

That's the whole idea: a handful of keys, and the voice keeps the pace I'd keep with my eyes.

## Who has the keyboard

A HUD that takes your keys is only welcome if it gives them back, so this part had to be precise. Voice Pipes never
comes to the front. The HUD is a small panel that can take the keyboard without making Voice Pipes the active app:
the app you're in stays in front, and when the HUD lets go, your typing goes straight back to it.

When it takes the keys is up to you, in **Setup → Reading → Keyboard while reading**:

- **Always** (the default since 1.8.1): the moment something starts being read. Great when an agent reads to you and
  your hands are already on the keyboard.
- **Point or click**: when you move the pointer onto the HUD, or click it. Move away and the keys are yours again
  (unless you clicked it; then click elsewhere). The HUD appearing under a resting pointer doesn't count.
- **Click**: only when you click the HUD. Nothing is taken until you ask; click anywhere else to give them back.
- **Never**: no keys at all. The HUD's buttons still work with the mouse, and so do any shortcuts you've set to work
  anywhere (more on those below).

<figure class="fig">
<div class="card fig__frame">
<div class="fig__label">Where your keys go, step by step</div>
<div class="rk-table">
<table class="rk-modes">
<thead><tr><th scope="col">While reading, you…</th><th scope="col">Always</th><th scope="col">Point or click</th><th scope="col">Click</th><th scope="col">Never</th></tr></thead>
<tbody>
<tr><th scope="row">start a reading</th><td class="rk-hud">HUD</td><td>app</td><td>app</td><td>app</td></tr>
<tr><th scope="row">move the pointer onto the HUD</th><td class="rk-hud">HUD</td><td class="rk-hud">HUD</td><td>app</td><td>app</td></tr>
<tr><th scope="row">move it away</th><td class="rk-hud">HUD</td><td>app</td><td>app</td><td>app</td></tr>
<tr><th scope="row">click the HUD</th><td class="rk-hud">HUD</td><td class="rk-hud">HUD</td><td class="rk-hud">HUD</td><td>app</td></tr>
<tr><th scope="row">click your app</th><td>app</td><td>app</td><td>app</td><td>app</td></tr>
<tr><th scope="row">the reading ends</th><td>app</td><td>app</td><td>app</td><td>app</td></tr>
</tbody>
</table>
</div>
<p class="fig__note">“HUD”: its keys work, and everything else you type is held back. “app”: your keys go to the app you're in, as usual.</p>
</div>
<figcaption>Read top to bottom: who has the keyboard after each step, in each mode. Worked out from the app's source (1.8.1), not a recording.</figcaption>
</figure>

The fine print, in plain words:

- **While the HUD has the keyboard, it really has it.** Keys that aren't one of its own are held back rather than
  typed into your app (and it doesn't beep at you). That's the trade with **Always**: to type, click your app, and
  the keys go straight back.
- **Any ⌘ shortcut hands the keyboard back.** The HUD lets go instead of acting on it, so a ⌘ press never reaches
  Voice Pipes' own menu (⌘Q included). That press is spent on letting go; press it again for your app.
- **The mouse is never taken.** Only while something is being read does the HUD's own patch at the bottom of the
  screen answer clicks (its buttons and the sentences in the card). Everywhere else, and the rest of the time, clicks
  go where they always do.
- **Clicking away** keeps reading by default. Set **When I click away** to **Stop** and clicking elsewhere ends the
  reading too.
- **No extra permission.** The HUD sees keys only while it is the window they go to. The anywhere shortcuts are
  ordinary system hotkeys, switched on only while something is being read.
- When the HUD has the keys, the tag shows **KEYS** and the card's foot **KEYS ON**. No mark, no keys taken.

## Make the keys yours

Vim keys suit me; they don't have to suit you. Every action's keys are in the same place, under **Keys while the HUD
has the keyboard**: each key is a chip with its ×, **+ key** adds another, and **Reset to defaults** brings back Esc,
Space, j/k, h/l and g/G. An action can have several keys, or none. Plain letters are fine here, because they only
work while the HUD has the keyboard.

Two keys behave differently. Plain Esc can't be recorded with **+ key**, because Esc cancels recording; it comes back
with **Reset to defaults** or in the config file. And anything with ⌘ always hands the keyboard back rather than
doing an action, so leave ⌘ out of these.

Below that, **Anywhere while reading** is for shortcuts that work in any app, without the HUD having the keyboard,
but only while something is being read. None are set until you add one with **+ Add shortcut**, and each needs ⌃, ⌥
or ⌘, so it never takes a key from your typing. ⌃⌥→ for faster, say, works even in **Never** mode.

<figure class="fig">
<div class="card fig__frame rk-setup" aria-hidden="true">
<div class="rk-section">Reading</div>
<div class="rk-panel">
<div class="rk-group"><span class="rk-strong">Keyboard while reading</span><span class="rk-seg"><span class="rk-seg__on">Always</span><span>Point or click</span><span>Click</span><span>Never</span></span><span class="rk-cap">As soon as something is read aloud, its keys work. Your app stays in front; click it to type again.</span></div>
<div class="rk-group"><span class="rk-strong">When I click away</span><span class="rk-seg"><span class="rk-seg__on">Keep reading</span><span>Stop</span></span></div>
<div class="rk-rule"></div>
<div class="rk-head"><span class="rk-strong">Keys while the HUD has the keyboard</span><span class="rk-reset">Reset to defaults</span></div>
<div class="rk-act"><span class="rk-act__label">Stop and close</span><span class="rk-chips"><span class="rk-chip">Esc<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Pause / resume</span><span class="rk-chips"><span class="rk-chip">Space<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Next sentence</span><span class="rk-chips"><span class="rk-chip">J<i>×</i></span><span class="rk-chip">↓<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Previous sentence</span><span class="rk-chips"><span class="rk-chip">K<i>×</i></span><span class="rk-chip">↑<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Slower</span><span class="rk-chips"><span class="rk-chip">H<i>×</i></span><span class="rk-chip">-<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Faster</span><span class="rk-chips"><span class="rk-chip">L<i>×</i></span><span class="rk-chip">=<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Back to the start</span><span class="rk-chips"><span class="rk-chip">G<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-act"><span class="rk-act__label">Last sentence</span><span class="rk-chips"><span class="rk-chip">⇧ G<i>×</i></span><span class="rk-add">+ key</span></span></div>
<div class="rk-rule"></div>
<div class="rk-group"><span class="rk-strong">Anywhere while reading</span><span class="rk-cap">Shortcuts that work in any app, but only while something is being read. Include ⌃, ⌥ or ⌘ so they don't take a key from your typing.</span><span class="rk-link">+ Add shortcut</span></div>
</div>
</div>
<figcaption>Illustrative recreation of Setup → Reading in Voice Pipes 1.8.1 with the default settings, not a screenshot. Letters show as capitals, as they do on the keys.</figcaption>
</figure>

It's all in `config.toml` too, under `[settings.reading]`, and the app picks up a saved change within a second:

```toml
[settings.reading]
take_keys = "click"           # always | hover (point or click) | click | never
click_away = "keep-reading"   # keep-reading | stop
faster = ["l", "equal", "period"]

[settings.reading.global]     # work in any app, only while something is read
faster = "control+option+right"
slower = "control+option+left"
```

Or from a terminal (`vp reading key` replaces that action's keys):

```sh
vp reading keys click
vp reading key faster l period
vp reading shortcut faster control+option+right
```

And if you'd rather not touch either, tell your agent "don't take my keys", and its skill changes the setting for
you. The [config guide](/docs/config) covers the file, and the [CLI reference](/docs/cli#vp-speed) the other reading
commands, like `vp speed` from another shell.

## Try it

Steering from the keyboard arrived in 1.7.3, and 1.8.1 made **Always** the default. If you already have Voice Pipes,
update from the menu bar panel. If you don't, one line installs it:

```sh
curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash
```

Then select something you half know, press <kbd>⌥R</kbd>, open the card from the tag, and read along. Skim with
<kbd>l</kbd>, slow down with <kbd>h</kbd>, and when a sentence slips by, <kbd>k</kbd>. A page never asked me to
read at its speed. Now the voice doesn't either.
