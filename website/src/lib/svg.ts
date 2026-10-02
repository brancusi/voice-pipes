/** The drawing inside a supplied SVG file and its viewBox, so a component can place it at its own size and role
 *  while the file itself stays exactly as supplied. */
export function svgParts(raw: string): { viewBox: string; inner: string } {
  const open = raw.match(/<svg\b[^>]*>/)?.[0];
  const viewBox = open?.match(/viewBox="([^"]+)"/)?.[1];
  if (!open || !viewBox) throw new Error('Expected an <svg> with a viewBox');
  return { viewBox, inner: raw.slice(raw.indexOf(open) + open.length, raw.lastIndexOf('</svg>')) };
}
