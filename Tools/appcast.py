#!/usr/bin/env python3
"""Write the Sparkle update feed (appcast.xml) for one release, to stdout.

    Tools/appcast.py <version> <download-url> "<sign_update output>" <release-notes.md>

<sign_update output> is what Sparkle's sign_update prints for the zip:
    sparkle:edSignature="…" length="…"
The feed holds only the newest release; installed apps compare its version with their own.
"""
import html
import re
import sys
from email.utils import formatdate


def notes_html(markdown: str) -> str:
    """Just enough Markdown for our release notes: paragraphs, "- " lists, **bold**, `code`."""
    out, in_list = [], False
    for line in markdown.splitlines():
        text = html.escape(line.strip())
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
        is_item = text.startswith("- ")
        if is_item and not in_list:
            out.append("<ul>")
        if not is_item and in_list:
            out.append("</ul>")
        in_list = is_item
        if is_item:
            out.append(f"<li>{text[2:]}</li>")
        elif text:
            out.append(f"<p>{text}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    version, url, signed, notes_path = sys.argv[1:]
    attrs = dict(re.findall(r'([\w:]+)="([^"]*)"', signed))
    if "sparkle:edSignature" not in attrs or "length" not in attrs:
        sys.exit(f"expected sparkle:edSignature and length from sign_update, got: {signed!r}")
    with open(notes_path, encoding="utf-8") as f:
        notes = notes_html(f.read()).replace("]]>", "]]&gt;")
    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Voice Tools</title>
    <item>
      <title>Version {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url)}" type="application/octet-stream"
                 sparkle:edSignature="{html.escape(attrs['sparkle:edSignature'])}" length="{html.escape(attrs['length'])}"/>
    </item>
  </channel>
</rss>""")


if __name__ == "__main__":
    main()
