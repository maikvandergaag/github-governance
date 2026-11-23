#!/usr/bin/env python3
"""Stage tracked files linked from documentation without publishing inventories."""

import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

import markdown


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in ("href", "src") and value:
                self.targets.append(value)


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: stage-linked-docs.py REPOSITORY STAGING_DIRECTORY")
    repository = Path(sys.argv[1]).resolve()
    staging = Path(sys.argv[2]).resolve()
    tracked = set(
        subprocess.check_output(
            ["git", "-C", str(repository), "ls-files", "-z"]
        ).decode("utf-8").split("\0")
    )
    pending = list(staging.rglob("*.md"))
    seen = set()
    while pending:
        page = pending.pop()
        if page in seen:
            continue
        seen.add(page)
        relative = page.relative_to(staging)
        parser = Links()
        parser.feed(markdown.markdown(page.read_text(encoding="utf-8"), extensions=["fenced_code", "tables"]))
        for link in parser.targets:
            url = urlsplit(link)
            if url.scheme or url.netloc or not url.path or url.path.startswith("/"):
                continue
            source = (repository / relative.parent / unquote(url.path)).resolve()
            if not source.is_relative_to(repository):
                sys.exit(f"{relative}: link escapes repository: {link}")
            target = source.relative_to(repository)
            if target.parts[:2] == ("docs", "output"):
                sys.exit(f"{relative}: generated inventory must not be published: {link}")
            if target.parts and target.parts[0] in (".git", ".github", "compliance", "src", "tests"):
                continue
            destination = staging / target
            if destination.exists() or not source.is_file() or target.as_posix() not in tracked:
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source.read_bytes())
            if destination.suffix.lower() == ".md":
                pending.append(destination)


if __name__ == "__main__":
    main()
