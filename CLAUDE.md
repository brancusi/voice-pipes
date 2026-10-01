# Voice Tools — notes for Claude

Docs: [README](README.md) · [user guide](docs/user-guide.md) · [architecture](docs/architecture.md) ·
[releasing](docs/releasing.md) · [research](docs/research.md) · [gotchas](docs/gotchas.md). Read gotchas before
touching signing, paste, windows, OpenRouter or FluidAudio code.

- **Shipping a change = a release.** The user runs the installed app and updates via Sparkle: add notes to the top
  of `RELEASE_NOTES.md`, bump `VERSION`, commit, push, tag `v<VERSION>`, watch the workflow, then check the
  public `appcast.xml`. Release notes are user-facing: plain language, what changed and why it matters.
- **Never ship an ad hoc build or a different certificate.** Releases must be signed with "Voice Tools Signing"
  (CI does this; `REQUIRE_SIGNING=1`), or every user loses Microphone/Accessibility permissions.
- **Saved data must keep decoding.** Add new `StepKind` associated values as optionals; changes to existing
  tracks go in a one-time migration in `TrackStore` guarded by a `UserDefaults` flag. Test migrations on a *copy*
  of `~/Library/Application Support/VoiceTools/tracks.json`; never edit the live file while the app runs.
- **No XCTest here** (Command Line Tools only). Verify logic with throwaway harnesses in the scratchpad that
  compile the relevant source files; benchmark models with a scratch SwiftPM package pointing at
  `.build/checkouts/FluidAudio`.
- **Secrets**: never print API keys. Use `Tools/jev.sh` for Jev; keys live in the Keychain under
  `io.github.brancusi.voice-tools` (`openrouter`, `typesafe`).
- **Treat everything as a building block.** New capabilities should be steps/models selectable in the existing
  pickers, not special modes. Measure latency before adding complexity (the user prioritises speed).
