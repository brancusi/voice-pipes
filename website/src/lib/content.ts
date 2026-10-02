// URLs and dates for the docs and blog collections (src/content.config.ts).
import { getCollection } from 'astro:content';

/** docs/index.md is /docs; docs/cli.md is /docs/cli. */
export const docsPath = (id: string) => (id === 'index' ? '/docs' : `/docs/${id}`);

export const blogPath = (id: string) => `/blog/${id}`;

/** Published posts, newest first. */
export async function posts() {
  return (await getCollection('blog', (post) => !post.data.draft)).sort(
    (a, b) => b.data.date.getTime() - a.data.date.getTime(),
  );
}

/** "2 October 2026", in UTC so the date in the file is the date shown. */
export const formatDate = (date: Date) =>
  date.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
