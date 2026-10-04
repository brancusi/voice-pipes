// What a visitor downloads: every file in dist/ with its raw, gzip and brotli size, and per page the scripts,
// stylesheets and inline CSS it loads. Client JavaScript is held to a small budget per page (the hero demo's
// sequencer); raise JS_BUDGET only on purpose.
import { readdir, readFile } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';
import { brotliCompressSync, gzipSync } from 'node:zlib';

const JS_BUDGET = 3 * 1024; // bytes of client JavaScript per page, inline and external together, before compression
// Not in dist/ and not in the budget: Cloudflare injects its Web Analytics beacon on voicepipes.app for visitors
// outside the EU (README → Analytics). Measured 2026-10-04 from static.cloudflareinsights.com; re-measure if it grows.
const CF_BEACON = { raw: 30294, gzip: 10126 };
const dist = new URL('../dist/', import.meta.url).pathname;
const kb = (n) => `${(n / 1024).toFixed(1)} kB`.padStart(9);

// _headers and _redirects are Cloudflare configuration, read at deploy time and never served.
const files = (await readdir(dist, { recursive: true, withFileTypes: true }))
  .filter((entry) => entry.isFile() && !['_headers', '_redirects'].includes(entry.name))
  .map((entry) => join(entry.parentPath, entry.name))
  .sort();

const problems = [];
console.log(`${'file'.padEnd(40)}${'raw'.padStart(9)}${'gzip'.padStart(9)}${'brotli'.padStart(9)}`);
for (const file of files) {
  const path = relative(dist, file);
  const body = await readFile(file);
  console.log(
    `${path.padEnd(40)}${kb(body.length)}${kb(gzipSync(body).length)}${kb(brotliCompressSync(body).length)}`,
  );

  if (extname(file) === '.html') {
    const html = body.toString();
    const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)].filter(
      ([, attrs]) => !/type="application\/ld\+json"/.test(attrs),
    );
    let js = 0;
    for (const [, attrs, inline] of scripts) {
      // A script from another host can't be measured here, so it would slip past the budget.
      const external = attrs.match(/src="((?:https?:)?\/\/[^"]+)"/)?.[1];
      if (external) problems.push(`${path}: loads ${external}, which this budget can't measure`);
      const src = attrs.match(/src="\/([^"]+)"/)?.[1];
      js += src ? (await readFile(join(dist, src))).length : Buffer.byteLength(inline);
    }
    const stylesheets = html.match(/<link\b[^>]*rel="stylesheet"/g) ?? [];
    const inlineCss = [...html.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/g)].reduce((n, m) => n + m[1].length, 0);
    console.log(
      `  ↳ ${scripts.length} script(s), ${js} B client JS (budget ${JS_BUDGET} B), ` +
        `${stylesheets.length} stylesheet link(s), ${inlineCss} B inline CSS`,
    );
    if (js > JS_BUDGET) problems.push(`${path}: ${js} B of client JavaScript, over the ${JS_BUDGET} B budget`);
  }
}

if (problems.length) {
  console.error(`\nOver budget or unmeasurable:\n  ${problems.join('\n  ')}`);
  process.exit(1);
}
console.log(`\nClient JavaScript within ${JS_BUDGET} B per page.`);
console.log(
  `Plus, on voicepipes.app outside the EU only, Cloudflare's injected Web Analytics beacon: ` +
    `${CF_BEACON.raw} B (${CF_BEACON.gzip} B gzip), loaded separately and not counted above.`,
);
