"""Regression checks for release versioning and example lockfiles."""

import json
import os
import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TRELLIS = shutil.which("trellis")


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for relative in (
            "gleam.toml",
            "manifest.toml",
            "examples/dotes/gleam.toml",
            "examples/dotes/manifest.toml",
        ):
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, destination)

    def trellis(self, *args):
        result = subprocess.run(
            [TRELLIS, "--no-update-check", "-C", str(self.root), *args],
            env={**os.environ, "PATH": ""},
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_release_updates_example_lockfile_without_releasing_example(self):
        changes = self.root / ".changes/unreleased"
        changes.mkdir(parents=True)
        (changes / "release-test.toml").write_text(
            'package = "slate"\nkind = "Fixed"\nbody = "Regression fixture."\n'
        )
        manifest = self.root / "examples/dotes/manifest.toml"
        before = manifest.read_text()
        version = tomllib.loads((self.root / "gleam.toml").read_text())["version"]
        example = (self.root / "examples/dotes/gleam.toml").read_bytes()
        root_lockfile = (self.root / "manifest.toml").read_bytes()

        result = self.trellis("version", "apply", "--json")

        self.assertEqual([bump["name"] for bump in result["bumped"]], ["slate"])
        next_version = result["bumped"][0]["next"]
        self.assertNotEqual(next_version, version)
        self.assertEqual(result["lockfiles"], ["examples/dotes/manifest.toml"])
        self.assertEqual(
            manifest.read_text(),
            before.replace(
                f'name = "slate", version = "{version}"',
                f'name = "slate", version = "{next_version}"',
            ),
        )
        self.assertEqual((self.root / "examples/dotes/gleam.toml").read_bytes(), example)
        self.assertEqual((self.root / "manifest.toml").read_bytes(), root_lockfile)
        matrix = self.trellis("ci", "matrix", "--releasable")
        self.assertEqual([package["name"] for package in matrix["include"]], ["slate"])

    def test_root_tasks_do_not_run_example_even_when_named(self):
        for task in ("build", "test", "check", "format", "docs", "deps", "clean"):
            with self.subTest(task=task):
                result = self.trellis("run", task, "dotes", "--json")
                self.assertEqual(result["results"], [])


if __name__ == "__main__":
    unittest.main()
