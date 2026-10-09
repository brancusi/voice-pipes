# Voice Pipes — notes for Claude

Docs: [README](README.md) · [user guide](docs/user-guide.md) · [architecture](docs/architecture.md) ·
[releasing](docs/releasing.md) · [gotchas](docs/gotchas.md) · [website](website/README.md). Read gotchas before touching signing, paste, windows, OpenRouter or FluidAudio code.
Internal notes ([research](docs/private/research.md), [brand](docs/private/brand.md), [website plan](docs/private/website/README.md))
live in `docs/private/`, which is git-ignored: this repo is public, so keep personal or business notes there.

- **Shipping a change = a release.** The user runs the installed app and updates via Sparkle: add notes to the top
  of `RELEASE_NOTES.md`, bump `VERSION`, commit, push, tag `v<VERSION>`, watch the workflow, then check the
  public `appcast.xml`. Release notes are user-facing: plain language, what changed and why it matters.
- **Never ship an ad hoc build or a different certificate.** Releases must be signed with "Developer ID Application:
  Aram Zadikian (7F3RGY9LG8)" and notarized (CI does this; `REQUIRE_SIGNING=1`, `REQUIRE_NOTARIZATION=1`), or every
  user loses Microphone/Accessibility permissions and Keychain access.
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
- **Design follows the design system.** The look is the "cowboy hacker" direction (Sundown palette, SF Mono, the
  pixel organ-pipe mark, the Wrangler mascot); see the design system's Philosophy section. `UI/Theme.swift`, `UI/HUD.swift`, `Tools/make_icon.swift` and `UI/MenuBarGlyph.swift`
  mirror it: change the design system and these together. Western flavour only in headlines and empty states;
  controls, settings and errors stay plain.
