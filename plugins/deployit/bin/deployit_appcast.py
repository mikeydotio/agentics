"""deployit_appcast — pure Sparkle appcast (RSS) rendering.

Shared by `deployit-backend` (renders the tailnet-only per-product feed from
the shared index on every request) and `deployit-release` (renders a
single-item feed for the GitHub-release channel at publish time). Kept
I/O-free and index-free on purpose: callers own reading the outer
`assets/appcast.template.xml` template and any index/build data, and own
writing the result to an HTTP response or a file. This module only knows how
to turn already-resolved values into escaped XML text.

Not executable — a library import, not a `deployit-*` CLI entry point.
"""

import datetime as _dt
import email.utils as _eut
import html
import string

_ITEM_TEMPLATE = string.Template("""    <item>
      <title>$title</title>
      <pubDate>$pubdate</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$short_version</sparkle:shortVersionString>
      <enclosure url="$enclosure_url" length="$length" type="application/octet-stream" sparkle:edSignature="$ed_signature" />
    </item>""")


def rfc822(iso: str) -> str:
    """Format an ISO-8601 timestamp as an RFC-822 date for an appcast <pubDate>.
    Uses email.utils so the day/month names are always RFC-English."""
    return _eut.format_datetime(_dt.datetime.fromisoformat(iso))


def render_item(*, title, pubdate, version, short_version, enclosure_url,
                length, ed_signature) -> str:
    """Render one appcast <item>. All inputs are raw (unescaped) values; this
    escapes each for its XML context (text vs. quoted attribute) before
    substitution."""
    return _ITEM_TEMPLATE.substitute(
        title=html.escape(str(title)),
        pubdate=html.escape(str(pubdate)),
        version=html.escape(str(version)),
        short_version=html.escape(str(short_version)),
        enclosure_url=html.escape(str(enclosure_url), quote=True),
        length=html.escape(str(length)),
        ed_signature=html.escape(str(ed_signature), quote=True),
    )


def render_appcast(template_text: str, *, title, link, items: str) -> str:
    """Substitute the outer appcast.xml template (`$TITLE`/`$LINK`/`$ITEMS`).
    `title`/`link` are raw and get escaped here; `items` is a pre-joined,
    already-escaped string of one or more `render_item()` blocks."""
    return string.Template(template_text).substitute(
        TITLE=html.escape(str(title)),
        LINK=html.escape(str(link), quote=True),
        ITEMS=items,
    )
