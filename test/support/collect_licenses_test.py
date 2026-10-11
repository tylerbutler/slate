"""Regression checks for consolidated native notices."""

import hashlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
source = Path(__file__).resolve().parents[2] / "priv/slate_lock/source/collect_licenses.py"
spec = importlib.util.spec_from_file_location("collect_licenses", source)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class NoticeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = {"name": "example", "version": "1.0.0", "license": "MIT",
                        "manifest_path": str(self.root / "Cargo.toml")}
        self.metadata = {"packages": [self.package]}
        self.license = {"id": "MIT", "source_path": "LICENSE-MIT",
                        "text": "Copyright Example contributor.",
                        "used_by": [{"crate": self.package}]}
        self.report = {"licenses": [self.license]}
        self.rendered = "- example 1.0.0\nCopyright Example contributor.\n"

    def notices(self):
        return collector.crate_notices(self.metadata, self.report, self.rendered)

    def test_keeps_attribution_and_deterministic_output(self):
        (self.root / "COPYRIGHT").write_text("Additional contributor.\n", encoding="utf-8")
        content, packages = self.notices()
        self.assertIn(b"Additional contributor.", content)
        self.assertEqual(packages[0]["attribution"], ["COPYRIGHT"])
        self.assertEqual(packages[0]["selected"], ["MIT"])
        self.assertEqual((content, packages), self.notices())

    def test_rejects_missing_or_extra_coverage(self):
        self.report["licenses"] = []
        with self.assertRaisesRegex(SystemExit, "coverage mismatch"):
            self.notices()
        self.report["licenses"] = [self.license]
        self.metadata["packages"] = []
        with self.assertRaisesRegex(SystemExit, "coverage mismatch"):
            self.notices()

    def test_rejects_generic_license_fallback(self):
        self.license["source_path"] = None
        with self.assertRaisesRegex(SystemExit, "Missing upstream license text"):
            self.notices()

    def test_rejects_clarification_warning_even_when_generator_succeeds(self):
        result = subprocess.CompletedProcess(
            ["cargo", "about", "generate"], 0, "{}",
            "[\x1b[33mWARN\x1b[0m] failed to validate all files specified in clarification\n",
        )
        with patch.object(collector.subprocess, "run", return_value=result) as run:
            with patch.object(collector.sys, "stderr", io.StringIO()):
                with self.assertRaisesRegex(SystemExit, "reported licensing warnings"):
                    collector.command("cargo", "about", "generate", "--locked", "--fail")
        self.assertEqual(run.call_args.args[0][:4], ("cargo", "about", "--color", "never"))

    def test_rejects_missing_rendered_text_or_component(self):
        self.rendered = "- example 1.0.0\n"
        with self.assertRaisesRegex(SystemExit, "Missing rendered license text"):
            self.notices()
        self.rendered = self.license["text"]
        with self.assertRaisesRegex(SystemExit, "Missing rendered crate attribution"):
            self.notices()

    def test_check_does_not_write_and_rejects_missing_or_changed_output(self):
        files = {"THIRD_PARTY_NOTICES.txt": b"Expected notices\n"}
        with self.assertRaisesRegex(SystemExit, "Refresh native license notices"):
            collector.write_or_check(files, self.root, True)
        self.assertFalse((self.root / "THIRD_PARTY_NOTICES.txt").exists())
        collector.write_or_check(files, self.root, False)
        collector.write_or_check(files, self.root, True)
        path = self.root / "THIRD_PARTY_NOTICES.txt"
        path.write_bytes(b"Changed notices\n")
        with self.assertRaisesRegex(SystemExit, "Refresh native license notices"):
            collector.write_or_check(files, self.root, True)
        self.assertEqual(path.read_bytes(), b"Changed notices\n")

    def test_check_rejects_obsolete_notices_without_deleting_them(self):
        files = {"rust/current.txt": b"Current notice\n"}
        collector.write_or_check(files, self.root, False)
        obsolete = self.root / "rust/obsolete.txt"
        obsolete.write_bytes(b"Obsolete notice\n")
        with self.assertRaisesRegex(SystemExit, "Obsolete native license notices.*rust/obsolete.txt"):
            collector.write_or_check(files, self.root, True)
        self.assertEqual(obsolete.read_bytes(), b"Obsolete notice\n")

    def test_refresh_removes_obsolete_notices(self):
        old = {"rust/obsolete.txt": b"Obsolete notice\n", "old.txt": b"Old notice\n"}
        collector.write_or_check(old, self.root, False)
        current = {"rust/current.txt": b"Current notice\n"}
        collector.write_or_check(current, self.root, False)
        self.assertFalse((self.root / "rust/obsolete.txt").exists())
        self.assertFalse((self.root / "old.txt").exists())
        self.assertEqual((self.root / "rust/current.txt").read_bytes(), b"Current notice\n")
        collector.write_or_check(current, self.root, True)

    def test_preserves_runtime_and_rejects_changes(self):
        name = "rust/COPYRIGHT-library.html"
        path = self.root / name
        path.parent.mkdir()
        path.write_bytes(b"Original runtime notice\n")
        index = {"rust": "rustc test", "checksums": {
            name: hashlib.sha256(path.read_bytes()).hexdigest(),
        }}
        (self.root / "manifest.json").write_text(json.dumps(index), encoding="utf-8")
        files = collector.runtime_files(self.root, "rustc test", False)
        self.assertEqual(files[name], path.read_bytes())
        with self.assertRaisesRegex(SystemExit, "Rust toolchain changed"):
            collector.runtime_files(self.root, "rustc changed", False)
        path.write_bytes(b"Changed runtime notice\n")
        with self.assertRaisesRegex(SystemExit, "Changed Rust runtime notice"):
            collector.runtime_files(self.root, "rustc test", False)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            collector.runtime_files(self.root, "rustc test", False)


if __name__ == "__main__":
    unittest.main()
