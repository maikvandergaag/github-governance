#!/usr/bin/env python3
"""Build the public check catalog from the repository's check definitions."""

import json
import sys
from pathlib import Path


SCOPES = (("enterprise", "Enterprise"), ("org", "Organization"), ("repo", "Repository"))


def load_checks(repository):
    checks = []
    for path in sorted((repository / "tests").glob("*/check.json")):
        manifest = json.loads(path.read_text(encoding="utf-8"))
        policy = json.loads((path.parent / "policy.json").read_text(encoding="utf-8"))
        check_id = manifest["id"]
        if check_id != path.parent.name or manifest["scope"] not in dict(SCOPES):
            raise ValueError(f"Invalid check identity or scope in {path}")
        template = (path.parent / "issue.md").read_text(encoding="utf-8")
        lines = template.splitlines()
        if lines and lines[0].startswith("#"):
            lines = lines[1:]
        guidance = "\n".join(line for line in lines if "{{" not in line).strip()
        checks.append((manifest, policy, guidance, (path.parent / "README.md").is_file()))
    if not checks:
        raise ValueError("No check manifests found")
    return checks


def render_check(manifest, policy, guidance, has_readme):
    enabled = "Enabled" if policy["enabled"] else "Disabled"
    text = (
        f"# {manifest['title']}\n\n"
        f"**Check:** `{manifest['id']}`  \n"
        f"**Scope:** {dict(SCOPES)[manifest['scope']]}  \n"
        f"**Default:** {enabled}, {policy['severity']} severity\n\n"
        f"{guidance}\n\n"
    )
    if not guidance:
        text += f"## Remediation\n\n{manifest['remediation']}\n\n"
    if policy.get("params"):
        text += "## Default parameters\n\n```json\n"
        text += json.dumps(policy["params"], indent=2, ensure_ascii=False)
        text += "\n```\n\n"
    if has_readme:
        text += "[Detailed check guidance](README.md)\n\n"
    text += (
        "[Check catalog](../../docs/checks.md) · "
        "[Policy and outcomes](../../docs/configuration/04-policy.md)\n"
    )
    return text


def render_catalog(checks):
    text = (
        "# Governance check catalog\n\n"
        "Browse the built-in checks by scope. Severity and parameters shown here are local "
        "defaults; your policy can override them. Missing data is not treated as a pass.\n\n"
        "Checks are starting points, not proof of regulatory compliance. Any CIS benchmark "
        "references describe partial assessments and do not establish certification.\n\n"
        "[Configure policy](configuration/04-policy.md) · "
        "[Add a check](configuration/06-adding-checks.md)\n\n"
    )
    for scope, label in SCOPES:
        text += f"## {label} checks\n\n"
        text += "| Check | Requirement | Default severity | State |\n| --- | --- | --- | --- |\n"
        for manifest, policy, _, _ in checks:
            if manifest["scope"] != scope:
                continue
            title = manifest["title"].replace("|", "\\|")
            state = "Enabled" if policy["enabled"] else "Disabled"
            text += (
                f"| [`{manifest['id']}`](../tests/{manifest['id']}/issue.md) "
                f"| {title} | {policy['severity']} | {state} |\n"
            )
        text += "\n"
    text += (
        "## Running checks\n\n"
        "The workflow uses the central policy. For local and individual checks, see "
        "[testing and execution](repo/README.md#tests).\n"
    )
    return text


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: generate-check-catalog.py REPOSITORY STAGING_DIRECTORY")
    repository = Path(sys.argv[1])
    staging = Path(sys.argv[2])
    checks = load_checks(repository)
    for manifest, policy, guidance, has_readme in checks:
        destination = staging / "tests" / manifest["id"] / "issue.md"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            render_check(manifest, policy, guidance, has_readme), encoding="utf-8"
        )
    (staging / "docs" / "checks.md").write_text(render_catalog(checks), encoding="utf-8")


if __name__ == "__main__":
    main()
