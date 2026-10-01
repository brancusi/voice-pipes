Voice Tools: a menu bar app that runs tracks, hotkey-triggered pipelines for dictation and read-aloud.

**0.1.0**
- **Tracks**: each one is a pipeline of steps you build in **Edit tracks…**. Audio or text goes in (microphone, selected text, current page, clipboard, previous clipboard), passes through steps (Parakeet v3 on this Mac, OpenRouter transcription, an LLM, an HTTP request, a template) and comes out pasted, copied, spoken, or posted somewhere.
- **Triggers**: any number of hotkeys per track, each **Toggle** (press to start, press to stop) or **Press & hold**. Esc cancels a recording.
- **Fast dictation** (⌥ Space, hold): Parakeet v3 on this Mac. Speech is transcribed at each pause while you talk, so the text appears almost as soon as you let go.
- **Clean dictation** (⌥ ⇧ Space): MAI-Transcribe-2, then Claude Haiku tidies the text, both through OpenRouter. Add your key in Edit tracks → Connections.
- **Read aloud** (⌥ R): reads the selection, or the page, or the clipboard. Press again to pause and again to resume from the same word.
- **Checks**: microphone and Accessibility permissions, the Parakeet model, your OpenRouter key, and shortcut clashes, with a button to fix each.
- **Updates itself**: checks every 5 minutes and when the panel opens; the menu bar icon becomes a download arrow and the panel offers **Install…**.
