# Brand assets

Components draw these at whole-pixel sizes (`src/lib/svg.ts`); don't redraw them by hand. The Wrangler in boots and
spurs comes from the "Voice Pipes App · Sundown" canvas (revision 1790937768-cad3), which has him only inline: his 22
`<path>` elements are copied verbatim from its History artboard into a plain `<svg>` wrapper.

The site's mark is the one-colour version of the logo, so it reads at header size: the full-colour Sundown mark (pipes
against a banded sky) blurs into a smudge at 32 px. The Sundown mark stays the app icon and lives in the design system
and `Tools/make_icon.swift`.

| File | Use on the site |
| --- | --- |
| `voicepipes-glyph.svg` | The mark, one colour (`currentColor`), 18 × 18: the header lockup (`Logo.astro`), drawn at 36 px. The `›` prompt, three pipes with their slits cut out and the base pipe, as on the logo canvas's one-colour menu bar glyph ("Favicon and small sizes", revision 1790969857-e7d0) |
| `voicepipes-favicon-16.svg` | The same drawing redrawn for 16 px, bone on a violet (`#2a2140`) tile so it reads on light and dark browser tabs: the favicon (`src/pages/favicon.svg.ts`) |
| `wrangler-busk-boots.svg` | The Wrangler busking with his harmonica, in boots and spurs: the hero and the closing call to action |
