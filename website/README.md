# Voice Pipes website

The marketing site for [voicepipes.app](https://voicepipes.app): [Astro](https://astro.build), pre-rendered to plain
HTML and CSS, served by Cloudflare Workers static assets. The plan, copy and sitemap are in
[docs/website](../docs/website/README.md).

**Status: home page implemented, previewed, not in production.** The home page is the "Home · voicepipes" artboard
of the Voice Pipes Website design (a Claude design canvas), built on the Voice Pipes design system (its Philosophy,
Sundown tokens, components and logo rules) with the system's own logo and mascot files. See `docs/brand.md` for the
direction. `/setup` is the key setup guide the app links to (`/setup#openrouter`, `/setup#jev`; keep those anchors).
`/docs` is the developer docs (terminal install, the `vp` reference, config.toml, agents) and `/blog` the blog, both
written in Markdown (see Writing below). The other pages in the sitemap aren't designed yet.

This folder is independent of the Mac app: `build.sh`, `Package.swift` and the release workflow never read it, and a
website change is not an app release (no `VERSION` bump or release notes).

## Commands

Node 22.12 or later.

```sh
npm ci               # install exactly what package-lock.json pins
npm run dev          # dev server on http://localhost:4321
npm run check        # astro check: TypeScript and Astro diagnostics
npm run build        # → dist/
npm run payload      # what each page downloads (raw, gzip, brotli); fails if a page's client JS passes 3 kB
npm run verify       # check + build + payload
npm run preview      # build, then serve dist/ with Wrangler's local Cloudflare runtime (production routing,
                     # 404 page and _headers) on http://localhost:8787
```

## Layout

| Path | What |
| --- | --- |
| `src/pages/` | One file per URL. `features/speed.astro` builds to `features/speed.html`, served at `/features/speed` |
| `src/components/` | The home page's sections, in page order from `SiteHeader` to `SiteFooter`; `HeroDemo` is the illustrative demo |
| `src/pages/setup.astro` | The key setup guide: what needs which key, OpenRouter and TypeSafe steps, where keys go in the app |
| `src/content/docs/` | The developer docs, one Markdown file per page; `src/pages/docs/[...slug].astro` renders them with the sidebar |
| `src/content/blog/` | Blog posts, one Markdown file each; `src/pages/blog/` has the index, the post page and `rss.xml`; `FlowFigures.astro` steps a post's animated figures |
| `src/content.config.ts` | The two collections and their front matter |
| `src/layouts/Base.astro` | The document shell: title, description, canonical URL, `noindex`, fonts, skip link |
| `src/styles/global.css` | All styles: the design system's colour tokens, the design's classes and its two breakpoints (900 and 520 px) |
| `src/lib/releases.ts` | Reads the newest releases from the app's `RELEASE_NOTES.md` for the Changelog section |
| `src/assets/brand/` | The design system's logo and mascot SVGs, unchanged; `src/lib/svg.ts` draws them at whole-pixel sizes |
| `src/pages/favicon.svg.ts` | Serves the supplied 16 px mark as `/favicon.svg` |
| `src/site.ts` | The download and release-notes links (the public `voice-tools-releases` repository) |
| `public/` | Copied to `dist/` as is: `_headers` for Cloudflare's response headers |
| `scripts/payload.mjs` | The payload report behind `npm run payload` |
| `wrangler.jsonc` | Cloudflare hosting: the asset directory, 404 handling and the custom domain |

## Writing docs and posts

- **A blog post** is a Markdown file in `src/content/blog/`; its file name is its URL (`my-post.md` → `/blog/my-post`).
  Front matter: `title`, `description` (the index and the feed use it) and `date` (`2026-10-02`); `draft: true`
  keeps it out of the build. The index, the post page and `/blog/rss.xml` pick it up.
- **A docs page** is a Markdown file in `src/content/docs/` (`index.md` is `/docs`). Front matter: `title`, `nav` (its
  sidebar name), `description`, `order` (its place in the sidebar) and optionally `headline` (the big lowercase
  heading; the title, lowercased, by default). `##` headings become the sidebar's sections, `###` their subsections.
- **Figures** in a post are plain HTML in the Markdown file, using the `fig__*` classes in `global.css` (see
  `why-i-built-voice-pipes.md`; keep each figure free of blank lines). In `<figure data-flow>`, elements with
  `data-step="n"` appear one stage at a time (`FlowFigures.astro`); without JavaScript or with reduced motion
  everything shows at once. Label recreations of the app as illustrative, not screenshots.
- Code blocks are plain (no highlighter). Fence commands as `sh` and they get a Copy button; fence sample output as
  `text` and they don't.
- Docs describe the app as shipped: check commands against the CLI source (`Sources/VoiceTools/CLI/`) and
  `Tools/install.sh`, and say which version a page matches. Don't link the private repository as documentation.

## Content that comes from the app

- **Changelog** lists the newest four entries of `RELEASE_NOTES.md` at the repository root, summarised by each
  bullet's bold lead, so it is current after every release. The build reads `../RELEASE_NOTES.md`, so it needs the
  whole repository (as Workers Builds checks it out), not `website/` alone.
- Figures and models on the page come from `docs/research.md` and the app's code (`Stats.astro` and `Routing.astro`
  name their sources).

## Where it differs from the design

- **Header below 1100 px:** the section links are hidden (the design's stylesheet says 900 px; Docs and Blog, which
  stay on every screen, need the room). In the design an inline style overrides that rule, so on a phone the links
  wrap and push Download off-screen (the page scrolls sideways). Below 520 px Docs and Blog take a second row.
- **Changelog rows** come from the release notes (above), so the text differs from the design's 1.1.0-era sample.
- **Logo:** the header uses the design system's primary Sundown mark at 32 px (the design drew the 16 px three-pipe
  drawing there, which the system keeps for sizes under 32 px), in the system's horizontal lockup: a gap of a fifth of
  the icon and the wordmark tracked at -0.02em. The favicon is the supplied 16 px drawing.
- **Fonts** are served from this site instead of Google Fonts; **a skip link** and **pink focus rings** on every link
  (the design system's focus style) are added for keyboard use.
- **Animated hero (owner's request, 2026-10-02):** a saguaro, the Wrangler in boots and spurs playing his harmonica,
  notes drifting up, and an illustrative demo of five takes (terminal, email, read aloud, ask, notes) staged as
  capture, processing, done, with clearly labelled made-up timings. Pause, replay and a take picker; it holds still
  with reduced motion and pauses when the hero is off-screen or the tab is hidden.
- **Headlines in Ultra**, a readable western slab (the owner found Silkscreen hard to read large); Silkscreen stays as
  the accent on the small feature titles. Cowboy copy around takes ("brand your words", "no steer left behind").
- **The Wrangler in boots and spurs** in the hero and closing call to action. No booted singing pose exists yet, so
  both use the busking pose.
- **Copy matched to the app:** Tracks says three come set up (the app's defaults: Fast dictation, Clean dictation,
  Read aloud) and labels Quick answer a recipe with "your hotkey"; the changelog lede says updates are offered with
  **Install…** rather than installed by themselves; "new tricks most weeks" became "new tricks every release"; and
  local models are "downloaded once, then run offline" (the repository doesn't document Neural Engine use).
- **Contrast:** text the design set in the "comment" colour (timestamps, block notes, footer note, 3.2–3.7:1) uses
  `--fg-muted` instead, as the design system's own note on that token asks; it stays on the `›` marks.

## Keeping it fast

- **Almost no client JavaScript:** only the hero demo's sequencer (about 2 kB, inline). `npm run payload` holds each
  page to 3 kB. Everything else is CSS: the notes, the Wrangler's bob and the cursor are stepped CSS animations, still
  under reduced motion, and the demo shows a finished take without JavaScript.
- **CSS inlined** in each page (`build.inlineStylesheets: 'always'`) and the illustrations are inline SVG, so a page
  is its HTML plus the two fonts.
- **Fonts served from this site**, not a font CDN: Astro's Fonts API copies the latin JetBrains Mono (variable, every
  weight in one file) and Silkscreen files from the installed Fontsource packages, preloads both, and adds
  size-matched fallbacks so text doesn't jump when they arrive.
- Files under `/_astro/` are fingerprinted and cached for a year (`public/_headers`); HTML revalidates with an ETag
  on every visit, so a deploy shows up immediately.
- No adapter and no Worker script: Cloudflare serves the files directly, and static asset requests are free and
  unmetered.

## Hosting

Cloudflare's current Astro guide deploys a fully static site as Workers static assets with no adapter, so that is
the setup here (`wrangler.jsonc`):

| | |
| --- | --- |
| Worker | `voice-pipes-website` (no script, assets only) |
| Custom domain | `voicepipes.app`. Deploying attaches it, and Cloudflare creates the DNS record and certificate |
| Zone | `voicepipes.app` is on Cloudflare nameservers; it had no DNS records on 2026-10-02 |
| Account | Whichever account the Wrangler login uses. It must be the one holding the `voicepipes.app` zone (`account_id` is unset) |
| workers.dev | Production isn't (`workers_dev: false`); Previews are, at `<preview>-voice-pipes-website.<subdomain>.workers.dev` with `X-Robots-Tag: noindex` |

Nothing is in production yet. To publish an approved version:

1. `npm ci && npm run verify`
2. Log in to the Cloudflare account that holds `voicepipes.app` (`npx wrangler login`, or a `CLOUDFLARE_API_TOKEN`
   allowed to edit Workers scripts and the zone's Workers routes and DNS).
3. `npx wrangler deploy` publishes `dist/` to production and attaches `voicepipes.app` on the first run.

Still to set up when the site goes live:

- **www.voicepipes.app.** A Custom Domain only answers its exact hostname, so `www` needs a proxied DNS record and a
  redirect rule to the apex in the zone
  ([Cloudflare's guide](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)).
- **Automatic deploys** (optional). Workers Builds can build and deploy on push: connect this repository in the
  Cloudflare dashboard with root directory `website`, build command `npm run build` and deploy command
  `npx wrangler deploy`.

## Previews

[Worker Previews](https://developers.cloudflare.com/workers/previews/) publish a build to its own public `workers.dev`
URL without touching production: Previews never take over routes or custom domains, and `voicepipes.app` is marked
`previews_enabled: false`. With the same login as above, from `website/`:

```sh
npm ci && npm run verify
npx wrangler preview --name pr-<number> --tag "$(git rev-parse --short HEAD)"   # needs Wrangler 4.135+ (the pinned one)
```

It prints the Preview URL (always the latest deployment of that Preview) and a deployment URL for that exact build.
`npx wrangler preview delete --name pr-<number>` removes a Preview and its deployments. Noindex keeps it out of search
results; it doesn't make it private.
