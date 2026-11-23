import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / ".github/scripts/generate-check-catalog.py"


class GenerateCheckCatalogTests(unittest.TestCase):
    def test_generates_catalog_and_guidance_from_check_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            check = root / "repo/tests/org.example"
            check.mkdir(parents=True)
            stage = root / "site"
            (stage / "docs").mkdir(parents=True)
            (check / "check.json").write_text(json.dumps({
                "id": "org.example", "scope": "org", "title": "Example check",
                "remediation": "Fix the setting.",
            }))
            (check / "policy.json").write_text(json.dumps({
                "enabled": False, "severity": "high", "params": {"max": 2},
            }))
            (check / "issue.md").write_text(
                "## Example check\n\n**Target:** [{{target}}]({{target_url}})\n\n"
                "A useful explanation.\n\n### Remediation\n\nFix the setting.\n"
            )
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(root / "repo"), str(stage)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            catalog = (stage / "docs/checks.md").read_text()
            page = (stage / "tests/org.example/issue.md").read_text()
            self.assertIn("../tests/org.example/issue.md", catalog)
            self.assertIn("Disabled", catalog)
            self.assertIn("A useful explanation.", page)
            self.assertIn('"max": 2', page)
            self.assertNotIn("{{", page)


if __name__ == "__main__":
    unittest.main()
