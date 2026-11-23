#!/usr/bin/env python3
"""Check local links and fragments in a built MkDocs site."""

import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "name" in attrs:
            self.ids.add(attrs["name"])
        for attr in ("href", "src"):
            if attr in attrs:
                self.links.append((attrs[attr], self.getpos()[0]))


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: validate-pages-links.py SITE_DIRECTORY SITE_URL")
    root = Path(sys.argv[1]).resolve()
    base = sys.argv[2].rstrip("/") + "/"
    base_url = urlsplit(base)
    if not root.is_dir() or base_url.scheme not in ("http", "https") or not base_url.netloc:
        sys.exit("A site directory and absolute HTTP(S) site URL are required.")

    pages = {}
    for path in root.rglob("*.html"):
        page = Page()
        page.feed(path.read_text(encoding="utf-8"))
        pages[path] = page
    if root / "index.html" not in pages:
        sys.exit("The site does not contain an index.html.")

    errors = []
    for path, page in pages.items():
        relative = path.relative_to(root).as_posix()
        url = urljoin(base, relative[:-10] if relative.endswith("index.html") else relative)
        for link, line in page.links:
            target = urlsplit(urljoin(url, link))
            if (target.scheme, target.netloc) != (base_url.scheme, base_url.netloc):
                continue
            if not target.path.startswith(base_url.path):
                errors.append((relative, line, link, "outside the site base path"))
                continue
            destination = (root / unquote(target.path[len(base_url.path):])).resolve()
            if not destination.is_relative_to(root):
                errors.append((relative, line, link, "outside the site directory"))
                continue
            if destination.is_dir():
                destination /= "index.html"
            if not destination.is_file():
                errors.append((relative, line, link, "missing file"))
            elif target.fragment and destination in pages and unquote(target.fragment) not in pages[destination].ids:
                errors.append((relative, line, link, "missing fragment"))

    for path, line, link, reason in errors:
        print(f"{path}:{line}: {link}: {reason}", file=sys.stderr)
    if errors:
        sys.exit(f"Found {len(errors)} broken site links.")
    print(f"Checked links in {len(pages)} HTML pages.")


if __name__ == "__main__":
    main()
