import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / ".github/scripts/stage-linked-docs.py"


class StageLinkedDocsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.site = self.root / "site"
        self.repo.mkdir()
        self.site.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)

    def write(self, root, name, content):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def run_staging(self):
        subprocess.run(["git", "-C", str(self.repo), "add", "-A"], check=True)
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.repo), str(self.site)],
            text=True,
            capture_output=True,
        )

    def test_stages_transitive_pages_and_reference_link_assets(self):
        self.write(self.site, "docs/page.md", "[Guide](../guide/start.md)")
        self.write(self.repo, "guide/start.md", "# Guide\n\n[Schema][schema]\n\n[schema]: ../schemas/test.json")
        self.write(self.repo, "schemas/test.json", '{"type":"object"}')
        self.write(self.repo, "schemas/unlinked.json", "{}")
        result = self.run_staging()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.site / "guide/start.md").is_file())
        self.assertTrue((self.site / "schemas/test.json").is_file())
        self.assertFalse((self.site / "schemas/unlinked.json").exists())

    def test_never_stages_generated_inventory_or_sensitive_paths(self):
        self.write(self.site, "docs/page.md", "[Inventory](output/private.json)")
        self.write(self.repo, "docs/output/private.json", "private")
        result = self.run_staging()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("generated inventory must not be published", result.stderr)
        self.assertFalse((self.site / "docs/output/private.json").exists())

        self.write(self.site, "docs/page.md", "[Policy](../compliance/policy.json)")
        self.write(self.repo, "compliance/policy.json", "private")
        result = self.run_staging()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.site / "compliance/policy.json").exists())

    def test_does_not_stage_untracked_or_code_block_links(self):
        self.write(self.site, "docs/page.md", "[Untracked](../untracked.json)\n\n```\n[Example](../example.json)\n```")
        self.write(self.repo, "example.json", "{}")
        self.write(self.repo, "untracked.json", "{}")
        subprocess.run(["git", "-C", str(self.repo), "add", "example.json"], check=True)
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.repo), str(self.site)],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.site / "untracked.json").exists())
        self.assertFalse((self.site / "example.json").exists())


if __name__ == "__main__":
    unittest.main()
