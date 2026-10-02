import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export interface Release {
  version: string;
  summary: string;
}

// The app's release notes at the repository root: `**x.y.z**` headings, newest first, then `- ` bullets that
// usually open with a **bold lead**. npm scripts run from website/, so the root is one level up.
const NOTES = resolve(process.cwd(), '../RELEASE_NOTES.md');

const plain = (text: string) => text.replace(/\*\*|`/g, '').trim();

/** The newest `count` releases, each summarised by the bold leads of its top-level bullets (or, for a release
 *  without any, the first sentence of its first bullet). Fails the build rather than show an empty changelog. */
export function latestReleases(count: number): Release[] {
  const releases: { version: string; bullets: string[] }[] = [];
  for (const line of readFileSync(NOTES, 'utf8').split('\n')) {
    const heading = line.match(/^\*\*(\d+\.\d+\.\d+)\*\*\s*$/);
    if (heading) releases.push({ version: heading[1], bullets: [] });
    else if (line.startsWith('- ')) releases.at(-1)?.bullets.push(line.slice(2));
  }

  const latest = releases.slice(0, count).map(({ version, bullets }) => {
    // A lead ending in ":" introduces a sub-list rather than saying what changed.
    const leads = bullets
      .map((b) => b.match(/^\*\*(.+?)\*\*/)?.[1])
      .filter((lead) => lead !== undefined && !lead.trim().endsWith(':'));
    const summary = leads.length
      ? leads.map((lead) => plain(lead!).replace(/[^.!?…]$/, '$&.')).join(' ')
      : plain(bullets[0]?.match(/^.*?[.!?](?=\s|$)/)?.[0] ?? bullets[0] ?? '');
    return { version, summary };
  });
  if (latest.length < count || latest.some((r) => !r.summary)) {
    throw new Error(`Expected ${count} summarised releases in ${NOTES}`);
  }
  return latest;
}
