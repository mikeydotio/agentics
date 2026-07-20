#!/usr/bin/env bash
# deployit_appcast is the shared, I/O-free Sparkle-appcast renderer used by both
# deployit-backend (tailnet feed) and deployit-release (GitHub-release feed).
# Pure Python stdlib — no macOS tools, no gate needed. Asserts: render_item
# escapes text/attribute content, emits the expected sparkle:* fields and a
# well-formed <enclosure>; render_appcast substitutes the outer template and
# the whole document parses as well-formed XML.
set -euo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

python3 - "$PLUGIN_ROOT" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys
import xml.dom.minidom as minidom

plugin_root = pathlib.Path(sys.argv[1])

loader = importlib.machinery.SourceFileLoader(
    "dappcast", str(plugin_root / "bin" / "deployit_appcast.py"))
spec = importlib.util.spec_from_loader("dappcast", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

# render_item escapes text content and quotes/escapes attribute content.
item = mod.render_item(
    title='Hello & "World" <App>',
    pubdate="Mon, 01 Jan 2024 00:00:00 -0000",
    version="42",
    short_version="1.2.3",
    enclosure_url="https://example.com/Hello & Friends.zip",
    length=12345,
    ed_signature='sig"with<special>&chars',
)
assert "<title>Hello &amp; &quot;World&quot; &lt;App&gt;</title>" in item, item
assert "<sparkle:version>42</sparkle:version>" in item, item
assert "<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>" in item, item
assert 'url="https://example.com/Hello &amp; Friends.zip"' in item, item
assert 'length="12345"' in item, item
assert 'sparkle:edSignature="sig&quot;with&lt;special&gt;&amp;chars"' in item, item
assert "<pubDate>Mon, 01 Jan 2024 00:00:00 -0000</pubDate>" in item, item

# render_appcast substitutes $TITLE/$LINK/$ITEMS and escapes title/link.
template = (plugin_root / "assets" / "appcast.template.xml").read_text()
doc = mod.render_appcast(
    template,
    title='App & Co (macOS)',
    link="https://example.com/p/id/macos/",
    items=item,
)
assert "<title>App &amp; Co (macOS)</title>" in doc, doc
assert "<link>https://example.com/p/id/macos/</link>" in doc, doc
assert item in doc, doc

# The whole document is well-formed XML.
minidom.parseString(doc)

# rfc822 formats an ISO-8601 timestamp as an RFC-822 <pubDate>.
formatted = mod.rfc822("2024-01-01T00:00:00+00:00")
assert formatted.startswith("Mon, 01 Jan 2024 00:00:00"), formatted

print("ok")
PY

echo "PASS"
