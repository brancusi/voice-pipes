// @ts-check
import { defineConfig, fontProviders } from 'astro/config';

// Fully pre-rendered: no adapter, no server output.
export default defineConfig({
  // The canonical origin; Base.astro builds each page's canonical link from it.
  site: 'https://voicepipes.app',
  // /features/speed → features/speed.html, served at the slash-less URLs in docs/website/copy-and-sitemap.md
  // without a redirect (Cloudflare's default html_handling, auto-trailing-slash, maps them).
  build: { format: 'file', inlineStylesheets: 'always' },
  trailingSlash: 'never',
  // Docs and blog code blocks are plain text styled by global.css (.prose pre): no highlighter's inline colours.
  markdown: { syntaxHighlight: false },
  // The site's three faces, served from this site (no font CDN). Latin only, from the installed Fontsource packages:
  // characters outside it fall back to the next font in the stack.
  fonts: [
    {
      provider: fontProviders.local(),
      name: 'JetBrains Mono',
      cssVariable: '--font-mono',
      fallbacks: ['SF Mono', 'ui-monospace', 'Menlo', 'monospace'],
      options: {
        variants: [
          {
            src: ['./node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2'],
            weight: '100 800',
            style: 'normal',
          },
        ],
      },
    },
    {
      // Large headlines: a Clarendon-style slab, readable at size with a wanted-poster feel (Apache-2.0).
      provider: fontProviders.local(),
      name: 'Ultra',
      cssVariable: '--font-display',
      fallbacks: ['Rockwell', 'Georgia', 'serif'],
      options: {
        variants: [
          { src: ['./node_modules/@fontsource/ultra/files/ultra-latin-400-normal.woff2'], weight: 400, style: 'normal' },
        ],
      },
    },
    {
      provider: fontProviders.local(),
      name: 'Silkscreen',
      cssVariable: '--font-pixel',
      fallbacks: ['monospace'],
      options: {
        variants: [
          {
            src: ['./node_modules/@fontsource/silkscreen/files/silkscreen-latin-400-normal.woff2'],
            weight: 400,
            style: 'normal',
          },
        ],
      },
    },
  ],
});
