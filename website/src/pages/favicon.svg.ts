// /favicon.svg is the mark's 16 px drawing on its violet tile, served exactly as drawn.
import favicon from '../assets/brand/voicepipes-favicon-16.svg?raw';

export const GET = () => new Response(favicon, { headers: { 'Content-Type': 'image/svg+xml' } });
