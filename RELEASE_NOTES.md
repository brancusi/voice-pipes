Voice Pipes (formerly Voice Tools): a menu bar app that runs tracks, hotkey-triggered pipelines for dictation and read-aloud.

**1.7.0**
- **Branches: one track, several paths.** The new **Branch · Jev** block asks Jev a question about the text, like "how hard is this to read aloud?" or "what is this about?", and runs the matching branch's own steps (any blocks, even another branch) before the track carries on. You decide what each branch does, right in the editor; Jev picks in about a third of a second.
- **Read aloud handles tricky text.** It now starts with a branch: plain prose is read as it is; text with numbers, prices or dates is first spelled out by a fast model (about 0.6 s), so "$4.2M" is read as "four point two million dollars"; code, file paths, URLs and tables are rewritten into sentences you can follow by ear. Want a different voice for the hard stuff? Add a Speak block to that branch. (New installs get this; to switch your existing Read aloud, add a Branch block, or ask your agent to.)
- **Download progress you can trust.** The model downloads in setup and in Setup → On this Mac now show a steady bar with "212 / 483 MB · 11 MB/s", then "preparing for this Mac…" while the model compiles. No more flickering, and the sizes shown are the real ones.

**1.6.5**
- **Click a sentence to jump there.** In the HUD's follow-along card, click any sentence and reading carries on from it, with any voice. Handy when an agent reads you a long summary: skip ahead to the part you care about, or go back over something you missed.
- **A running word cursor.** A thin underline moves along under the word being spoken, and the part of the sentence already read is a touch brighter. It's exact with macOS voices and closely estimated with the others.
- **Agents know they can read to you.** Ask Claude Code or another agent to read you its summary: the skill now tells it to write for listening, open the follow-along card and read it with Voice Pipes, then wait while you listen and steer.

**1.6.4**
- **Follow along with anything read aloud.** The HUD has a new button while it's reading: it opens a card above it with the whole text, one sentence per line, the one being read lit up and the card scrolling with the voice. Hover over it to look ahead; it picks up the voice again when you move away. Handy for long answers you didn't select yourself.
- **Speed it up or slow it down as it reads.** **−** and **+** on the card change the speed on the spot, from 0.6× to 2×, with every kind of voice. The card stays open for the next reading until you close it.
- `vp speed 1.4` changes the speed from a terminal; `vp open reading` / `vp close reading` show or hide the text.
- `vp ui` no longer reports a focused field after you've left the page it was on.

**1.6.3**
- **The command line keeps up by itself.** `vp` always runs the app's own version, so updating from the menu updates it too. Now the rest follows as well: the agent skill is refreshed at every launch, an agent you install later (say Codex) gets it automatically, and the Claude Code session hook follows the app. If you move Voice Pipes to another folder, `vp` is repointed at it; if that needs your password, Setup → Checks shows "vp points at a moved app" with a **Fix…** button.

**1.6.2**
- **Install everything from a terminal.** One line installs the app, the `vp` command and the agent skill, and starts Voice Pipes: `curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash`. It asks nothing, so an agent can run it too, and it refuses any download that isn't signed by Voice Pipes' developer and notarized by Apple. Run it again to repair or reinstall; `--uninstall` removes the app, its `vp` links and the skill, and keeps your config, history and keys.

**1.6.1**
- **Agents can show you, not just tell you.** `vp open` now reaches anything in the app: a track with one block's settings open (`vp open track clean-dictation --step 4`), a route card, the cursor in a field (`--field prompt`), History filtered to a track or a search, a word in Vocabulary, a section of Setup, a step of the setup window, or the menu bar panel (`vp open menu`). What it points at flashes, and it answers with what's on screen. `vp ui` prints that on its own; `vp close` closes windows, the panel or a sheet. No screen recording or Accessibility access involved. `--background` shows a window without taking your keyboard.
- **Watch a track being built.** When an agent (or you, in an editor) changes config.toml, the open track flashes what changed and opens a single new or changed block. The editor also stays where it was: a block you had open no longer closes on every save.

**1.6.0**
- **Your setup is now a file.** Tracks, hotkeys and settings live in `~/.config/voice-pipes/config.toml`, and the vocabulary in `vocabulary.toml` beside it: readable, commented TOML with a full block reference at the end and a schema your editor can check. Save and it applies within a second. If an edit doesn't check out, the last good version keeps running and Setup → Checks says what's wrong, on which line, with a "did you mean". Every change keeps a backup, including edits from outside the app, and a config.toml symlinked from your dotfiles stays linked. Your current tracks and words move over by themselves.
- **`vp`, the command line.** Setup → **Install command-line tool** (also a new step in the setup window) puts `vp` on your PATH. Run a track with text (`vp run clean-dictation --text "…"`, or pipe text in), speak (`vp say`), ask a question out loud and get the spoken answer back (`vp ask`), listen, transcribe a file on this Mac, browse history, edit vocabulary, check the config, and watch runs as they happen. It's built for agents: compact output, next-step hints, and no prompts.
- **Sign in to OpenRouter from the command line.** `vp auth login openrouter` opens the browser and saves the key to your Keychain; `vp auth set typesafe` takes a Jev key. Keys are never printed.
- **Secrets for your own endpoints.** `vp secret set notes`, then `${secret:notes}` in an HTTP block's URL, headers or body. The value stays in the Keychain, not in the file.
- **Agents know Voice Pipes.** Installing the command-line tool also installs a skill for Claude Code, Codex and other agents, so they can tell you things out loud, ask you questions by voice, run your tracks and safely edit your config.

**1.5.1**
- **Welcome to Voice Pipes, redrawn.** The first-run window has a step bar, plain titles, and live status: Continue waits until both permissions are on (or Skip), the models step shows Parakeet's download in MB and offers the optional Supertonic voices, the keys step links to openrouter.ai and lets you **Skip, stay local**, and Try it shows your first run's timings before the Wrangler tips his hat.
- **Empty pages with somewhere to go.** An empty Vocabulary offers **Train a word…** (type the spelling, then say it a few times); with no tracks left, **Restore the starter tracks** brings back Fast dictation, Clean dictation and Read aloud, leaving off any hotkey another track already uses.
- The setup window now opens centred, and a failed model download no longer leaves a stuck percentage.

**1.5.0**
- **A guided first launch.** New installs open **Set up Voice Pipes**: it explains and asks for Microphone and Accessibility one at a time, shows each one's status live, and opens a small helper beside System Settings. If Voice Pipes isn't in the Accessibility list, drag the helper's icon into it. The on-device models start downloading in the background straight away, with progress, then you can add API keys and try a hotkey. **Setup → Run setup again…** reopens it.
- **Install from a DMG.** Download Voice-Pipes.dmg, open it, and drag Voice Pipes onto Applications.
- **Hotkeys you can read.** Keycaps in the menu bar panel, the sidebar and the editor are bigger and bolder, and the panel's header shows the Voice Pipes mark in one colour.
- **The Wrangler on every empty page.** No words in Vocabulary, or no tracks left: he's there with what to do next and a button that does it.
- **Narrow windows, take two.** Every page now fits the narrowest tile: the editor's trigger and title rows and Setup's Appearance card rearrange instead of holding the window wide, and names and status codes never break mid-word.

**1.4.0**
- **Every screen in the Sundown look.** The editor, History, Vocabulary, Setup, word training and the menu bar panel now match the new design in both Daylight and Sundown: cards, log-style status codes, lavender selections, rose focus rings.
- **A cleaner track editor.** The title row has the track's colour, its name, Enabled and **▶ Run now**. Each step is its own row, outlined when open. Route · Jev shows each route as a card with its model and price (e.g. `$1/$5`) and what Jev chooses it by; click a route to edit it. Deleting a track now asks first.
- **History you can browse.** Runs are grouped by day, chips filter by track, and each run's steps are listed in order with their times, coloured by kind. A run that failed is highlighted with what went wrong.
- **The Wrangler moves in.** An empty History shows him busking ("quiet on the range"), training a word ends with his wink ("roped and branded"), and there's a new **About Voice Pipes** window with a pixel sundown. Open it from the ⓘ in the panel's footer.
- **Live words in the HUD.** With a streaming or chunked Parakeet mode, the HUD shows your words as they land, with a cursor.
- Your tracks' original colours switch to the matching Sundown colours, which also adjust for Daylight. Colours you picked yourself stay as they were.

**1.3.0**
- **Meet the Wrangler, in your menu bar.** The Voice Pipes cowboy now sits up there in his hat. While you're recording, he raises an arm and swings a lasso over his head, so you can tell at a glance that the mic is open.
- **Light, dark or Auto.** Setup → Appearance: **Auto** follows your Mac, **Daylight** is always light, **Sundown** is always dark. Applies to the whole app, menu bar panel included; the HUD stays dark either way.

**1.2.0**
- **Sundown.** Voice Pipes now wears its own colours: desert-earth backgrounds with sunset accents (dusk blue, cloud lavender, sunset rose, marigold, sage), or warm bone paper and ink in light mode. Colours still mean the same things: transcription blue, transforms lavender, outputs green, recording red.
- **A new icon.** Four organ pipes, slits and all, standing against a pixel sundown. Drawn pixel by pixel, so it stays sharp at every size. (Finder and the Dock can take a moment, or a restart, to pick it up.)
- **A new menu bar icon.** Three little pipes behind a `›` prompt. They jump while you're recording, and a dot appears when an update is waiting.

**1.1.3**
- **The window fits any tile.** The Voice Pipes window used to refuse to get narrower than about 900 points, so in yabai, Stage Manager or split screen it pushed past its space into the next window. It now shrinks to whatever space it's given and its pages squeeze to fit. In a very narrow space, a page scrolls left and right rather than spilling over. You can also hide the sidebar for more room.

**1.1.2**
- **A cleaner Setup page.** It now matches the rest of the app: cards of status rows (OK, INFO, WARN, FAIL) for Checks, Connections, On this Mac and Updates.
- **Simpler API keys.** A saved key now shows as its first characters, dots and its last four, e.g. `sk-or-v1-••••3f9a`. To change it, click the field and paste the new one: it's saved straight away, with no Save button, and the OpenRouter key is checked on the spot. **Remove key** deletes one. Keys are still kept in your Mac's Keychain.

**1.1.1**
- **The window works when it's narrow.** In split screen or a small tiled window, pages like Vocabulary were cut off on both sides. They now shrink to fit, and when there really isn't room they scroll left and right instead of hiding their edges.

**1.1.0**
- **A new look.** Voice Pipes now wears its own skin: the Dracula colour scheme (or its light twin, Alucard, when your Mac is in light mode) and one monospace typeface everywhere, like the HUD always had. It still works like a normal Mac app.
- **Colour means something.** Each kind of step has its colour: transcription cyan, transforms (LLM, Route · Jev, Fix words) purple, outputs green. Statuses read like a log: OK, INFO, WARN, FAIL, always with the word, never colour alone.
- The menu bar panel shows which track is playing, a NEW card when an update is ready, and the Jev route under Now playing. History rows confirm with a ✓ when copied.
- In the editor, step rows carry their category colour, the drag handle is ⋮⋮, the hotkey recorder turns pink while it listens, and the footer confirms the steps connect.

**1.0.0**
- **Voice Tools is now Voice Pipes.** Pipelines, and pipes you play from the keyboard, like an organ. The menu bar panel, the window, notifications and the app itself carry the new name.
- After this update the app renames itself in your Applications folder from "Voice Tools" to "Voice Pipes" and reopens once. Your tracks, history, vocabulary, keys and permissions all carry over; nothing to set up again.

**0.9.5**
- **History: never lose a dictation.** Everything your tracks produce is now kept, even after you quit, so if you clicked away and the paste went nowhere, it's still there. The menu bar panel shows the last three with a copy button each; **All →** opens **History** (it was called Activity) in the main window, where you can search everything you've said and copy any of it back.
- A run that fails partway (say, the paste had nowhere to go) still saves its text, marked with what went wrong.
- For Quick answer and Clean dictation, History shows what you said above the answer or the cleaned-up text.
- The last 1,000 runs are kept on your Mac. **Clear history…** in the History toolbar removes them.

**0.9.4**
- **A tidier menu bar panel.** Each track is now one line: its color, name and hotkey. Hover a track to see its steps; the full pipeline is in the Voice Tools window.
- **No more scrolling.** The panel grows to fit everything (tracks, what's playing, recent runs) instead of cutting off at a fixed height.

**0.9.3**
- **See which model is answering.** A line under the HUD names the model, and for Route · Jev the route Jev picked, how long it took and how sure it was, e.g. "quick → claude-haiku-4.5 · Jev 262 ms 100%".
- **Pause and stop from the HUD.** While an answer is being read aloud, the HUD has pause/play and stop buttons. Clicking them doesn't take focus from the app you're working in. Pressing the track's hotkey again still pauses and resumes too.

**0.9.2**
- **No more Keychain password after updates.** Voice Tools is now signed with an Apple Developer ID and notarized by Apple. Until now, every update made macOS ask for your login password before the app could read your OpenRouter and Jev keys. From the next update on, it won't.
- **One-time setup for this update:** macOS sees a newly signed app, so:
  - When asked for your Keychain password, enter it and choose **Always Allow** (once for each key).
  - Allow **Microphone** again, and turn **Accessibility** back on. The panel's **Checks** list has a **Fix…** button for each.
- New installs open with a double-click; no more right-click → Open.

**0.9.1**
- **Reorder steps by dragging.** Each step in a track now has a handle (☰) on its left. Drag it up or down and the other steps move aside as you go; let go and the pipeline runs in the new order. If a step's input no longer matches the one before it, the editor says so under the list.

**0.9.0**
- **Route · Jev: let Jev pick the model.** A new block under Transform (+ Add step → **Route · Jev**). Jev reads what you said and sends it down one of your routes, each with its own model and instructions. It starts with three: **quick** (Claude Haiku 4.5, a sentence or two), **web** (Perplexity Sonar, for news, weather, prices) and **deep** (Claude Sonnet 5.5, for advice, comparisons and explanations). Rename them, describe when each should be used, change their models, or add more.
- Choosing takes Jev about a quarter of a second. In 15 test questions it picked the route we would have every time.
- The HUD and Activity show what was picked and how long Jev took, e.g. "Jev 260 ms → web 100% · sonar", so you can see whether it's choosing well.
- To try it on **Quick answer**: add Route · Jev, drag it by its handle to just above the Speak step, and delete the old LLM step. Needs your TypeSafe (Jev) key in Setup; without it the first route answers.

**0.8.0**
- **Faster takes when training a word.** Click **Start takes** and say it; **Next take** (or Space) ends that take and starts the next one straight away; **Finish** (or Return) ends the last. No more stop/start for every take. A live level meter shows it's hearing you, and silent takes are caught instead of quietly kept.
- **Jev judges the results.** Add your TypeSafe (Jev) key in Setup → TypeSafe (Jev). After training, every way the word came out is sent to Jev, which scores how safe it is to replace everywhere — garbled versions of your word score high; real words, other names and coding or specialist terms score low. Each result shows its Jev score; those at 60% or more are pre-ticked. Without a key, the old dictionary check is used.

**0.7.0**
- **Train a word** (Vocabulary → **Train…** on any row). Record yourself saying it a few times; Voice Tools replays each take about 30 ways (faster, slower, quieter, with background noise) through Parakeet, and can also have the 36 on-device voices say it. You get every distinct way it came out, how often, and how often it was already right. Tick the ones to keep and **Add to Heard as**.
- Results that came up at least twice are pre-ticked; one-offs are listed but left unticked. Anything made only of ordinary words (like "aaron's attacking") is flagged, since adding it would also change those words when you mean them.
- Five takes take about 5 seconds; with the on-device voices, about 30 seconds the first time (loading the voices).

**0.6.1**
- **The Voice Tools window stays reachable.** While it's open, Voice Tools shows in the Dock and in ⌘Tab, so you can switch away and back. Close the window and it's back to menu-bar-only.
- Fixed the Vocabulary page: each word showed "Claude Code" as a label beside it and listed its Heard-as words twice. It's now a plain table: Write, Heard as, Always exact.
- Typing a comma in Heard as no longer gets tidied away while you type.

**0.6.0**
- **Vocabulary and Fix words.** A shared list of words transcription keeps getting wrong (Open Voice Tools… → **Vocabulary**): for each, the spelling you want and what comes out instead, e.g. **Claude Code** ← "cloud code, clawed code". The new **Fix words** block replaces them instantly (no model, nothing leaves your Mac): whole words only, any capitalization, punctuation kept.
- Capitalization: spellings with capitals ("OpenRouter", "macOS") are always written exactly; all-lowercase ones get a capital at the start of a sentence, unless you tick **Always exact** (for things like `kubectl`).
- A **Try it** box on the Vocabulary page shows the result as you type.
- Fix words is added once, right after transcription, to your dictation tracks. It starts with Claude Code, OpenRouter and FluidAudio; edit or remove them.
- LLM steps (like the Haiku cleanup) get your vocabulary as a glossary, so they keep your spellings too.

**0.5.1**
- **Transcribe and Speak are each one building block.** Add the block, then choose its model from a single list. **On this Mac** comes first (Parakeet v3 for Transcribe; Pocket TTS, Supertonic-3 or macOS voices for Speak), then every OpenRouter model for that job. The voice list below the model always matches what you picked, and speed carries over when you switch.
- **Pocket TTS is the default for Read aloud.** Your existing Read aloud track switches to it once (Alba voice, your speed kept). Pick any other model in the Speak block whenever you like.
- The Add step menu is shorter: one Transcribe, one Speak, instead of an entry per engine.

**0.5.0**
- **Voices that run on this Mac.** The Speak step has two new engines next to macOS and OpenRouter:
  - **Pocket TTS** streams speech as it's generated, so reading starts almost instantly (about 20 ms after the model is loaded). 26 voices. About 770 MB, downloaded once. It's Kyutai's research model, so check its license before any commercial use.
  - **Supertonic-3** is very fast (about 80× faster than real time) and small (about 100 MB). 10 voices (Female 1–5, Male 1–5).
- Each voice has a ▶ preview. Pause/resume (⌥R), speed and Clear work the same as other engines.
- Tracks that use an on-device voice load it when the app starts, so the first read doesn't wait. Setup shows each engine's status and has **Load now**.
- To try it: Open Voice Tools… → Read aloud → expand Speak → **Pocket TTS** or **Supertonic**.

**0.4.1**
- **A much smaller HUD**: a slim, translucent monospace tag at the bottom of the screen instead of the big card. `■ REC 00:04` while recording, `PROC 312ms` while processing, then a green `OK 186ms` that fades out in well under a second. Read aloud shows `READ 42%` / `PAUSED`. It ignores the mouse, so it never blocks a click.
- The HUD no longer shows the transcript; it's in Activity (Open Voice Tools…) if you want it.
- The time shown is the real work after you let go: restoring your clipboard after a paste now happens in the background instead of counting toward it.

**0.4.0**
- **Read aloud with OpenRouter voices.** The Speak step now has an engine switch: **macOS voice** or **OpenRouter**. With OpenRouter, pick a speech model (MAI-Voice, Gemini, MiniMax, Deepgram Aura, Kokoro and more) and one of its voices; every voice has a ▶ preview. Long text is read in passages: the first starts within a second or two and the next downloads while you listen. Pause, resume, speed and replay-this-passage all work.
- **Model pickers** for every OpenRouter step: search the live list of transcription, language and speech models, with prices. Or type any model id.
- **A full Voice Tools window** (menu bar → **Open Voice Tools…**): **Tracks** to build and edit, **Activity** with every run's full text and how long each step took, and **Setup** with checks, your OpenRouter key, the model list and updates.
- The menu bar panel is now a quick launcher: tracks, what's playing, the last few runs, and a single line when something needs fixing.
- To switch an existing Read aloud track: Open Voice Tools… → Read aloud → expand the Speak step → **OpenRouter**.

**0.3.1**
- **This update shouldn't ask for any permission.** From 0.3.0 on, macOS recognises new versions as the same app, so Microphone and Accessibility stay allowed.
- **Fix…** buttons in Checks: if Accessibility or the Microphone is ever missing, one click clears the old entry macOS kept (the kind that shows as switched on but doesn't work), asks again, and opens the right Settings page. No more removing and re-adding the app by hand. The panel updates by itself once it's allowed.

**0.3.0**
- **Permissions now stay granted across updates.** Releases are signed with a fixed certificate, so macOS recognises each new version as the same app. Updating to 0.3.0 asks one last time: turn Voice Tools on again in Privacy & Security → Accessibility (remove it with − and add it back if the switch already looks on).
- Fixed: **Paste at cursor** could do nothing when the trigger's ⌥/⇧ keys were still held (⌥ Space sent ⌥⌘V instead of ⌘V). It now waits for you to let go of the modifiers. The same fix applies to reading the selection for Read aloud.
- Paste and copy work on any keyboard layout (Dvorak, AZERTY…), not just QWERTY.
- If macOS hasn't allowed Accessibility, the HUD now says so and leaves the text on the clipboard for ⌘V, instead of failing silently.

**0.2.0**
- **Parakeet mode** (Edit tracks → the Parakeet step): **On release** (the default, and the most accurate: the whole recording is transcribed when you stop, about 0.2 s for 20 s of speech), **Chunk at pauses** (each phrase is transcribed when you pause), or **Streaming** (overlapping windows with live text in the HUD while you talk).
- Fixed: chunked dictation could cut phrases mid-word or lose quiet speech, because the pause detector slowly started treating speech as silence. It now follows the room's background level over the last few seconds and never drops speech.
- Chunks are at least 3 s long, so Parakeet has enough context; the default pause before a cut is 500 ms.
- If live transcription fails or comes back empty, the whole recording is transcribed instead.
- Existing tracks switch to **On release**; pick another mode per track if you want it.
- Tracks that can't be read are set aside as `tracks.unreadable-<time>.json` instead of being replaced.

**0.1.0**
- **Tracks**: each one is a pipeline of steps you build in **Edit tracks…**. Audio or text goes in (microphone, selected text, current page, clipboard, previous clipboard), passes through steps (Parakeet v3 on this Mac, OpenRouter transcription, an LLM, an HTTP request, a template) and comes out pasted, copied, spoken, or posted somewhere.
- **Triggers**: any number of hotkeys per track, each **Toggle** (press to start, press to stop) or **Press & hold**. Esc cancels a recording.
- **Fast dictation** (⌥ Space, hold): Parakeet v3 on this Mac. Speech is transcribed at each pause while you talk, so the text appears almost as soon as you let go.
- **Clean dictation** (⌥ ⇧ Space): MAI-Transcribe-2, then Claude Haiku tidies the text, both through OpenRouter. Add your key in Edit tracks → Connections.
- **Read aloud** (⌥ R): reads the selection, or the page, or the clipboard. Press again to pause and again to resume from the same word.
- **Checks**: microphone and Accessibility permissions, the Parakeet model, your OpenRouter key, and shortcut clashes, with a button to fix each.
- **Updates itself**: checks every 5 minutes and when the panel opens; the menu bar icon becomes a download arrow and the panel offers **Install…**.
