Voice Tools: a menu bar app that runs tracks, hotkey-triggered pipelines for dictation and read-aloud.

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
