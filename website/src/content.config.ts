// The blog and the developer docs are Markdown files: add a post or a page by adding a file (README → Writing).
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const blog = defineCollection({
  // src/content/blog/<slug>.md → /blog/<slug>
  loader: glob({ base: './src/content/blog', pattern: '*.md' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    date: z.coerce.date(),
    /** Keeps a post out of the index, the feed and the build. */
    draft: z.boolean().default(false),
  }),
});

const docs = defineCollection({
  // src/content/docs/<slug>.md → /docs/<slug>; index.md is /docs
  loader: glob({ base: './src/content/docs', pattern: '*.md' }),
  schema: z.object({
    title: z.string(),
    /** The page's big lowercase headline; the title, lowercased, when left out. */
    headline: z.string().optional(),
    /** The shorter name in the docs sidebar. */
    nav: z.string(),
    description: z.string(),
    /** Position in the sidebar. */
    order: z.number(),
  }),
});

export const collections = { blog, docs };
