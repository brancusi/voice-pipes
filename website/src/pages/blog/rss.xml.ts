// The blog's RSS 2.0 feed at /blog/rss.xml: every published post, newest first, with its description.
import type { APIRoute } from 'astro';
import { blogPath, posts } from '../../lib/content';

const escape = (text: string) =>
  text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export const GET: APIRoute = async ({ site }) => {
  const origin = site ?? new URL('https://voicepipes.app');
  const items = (await posts())
    .map((post) => {
      const url = new URL(blogPath(post.id), origin).href;
      return `    <item>
      <title>${escape(post.data.title)}</title>
      <link>${url}</link>
      <guid>${url}</guid>
      <pubDate>${post.data.date.toUTCString()}</pubDate>
      <description>${escape(post.data.description)}</description>
    </item>`;
    })
    .join('\n');
  const body = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Voice Pipes blog</title>
    <link>${new URL('/blog', origin).href}</link>
    <description>News and notes from the people building Voice Pipes.</description>
    <language>en</language>
${items}
  </channel>
</rss>
`;
  return new Response(body, { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } });
};
