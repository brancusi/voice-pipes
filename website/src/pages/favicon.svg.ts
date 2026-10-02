// /favicon.svg is the supplied 16 px drawing of the mark, served exactly as supplied.
import mark16 from '../assets/brand/voicepipes-mark-16.svg?raw';

export const GET = () => new Response(mark16, { headers: { 'Content-Type': 'image/svg+xml' } });
