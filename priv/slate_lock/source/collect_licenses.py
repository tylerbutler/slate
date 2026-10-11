"""Collect notices for the locked native dependencies and Rust standard library."""

import json
import hashlib
import subprocess
import sys
from pathlib import Path
from urllib.request import urlopen

source = Path(__file__).resolve().parent
destination = source.parent / "licenses"
check = sys.argv[1:] == ["--check"]
if sys.argv[1:] not in ([], ["--check"]):
    raise SystemExit("Usage: collect_licenses.py [--check]")


def command(*args):
    return subprocess.check_output(args, cwd=source, text=True, encoding="utf-8")


files = {}
packages = []
metadata = json.loads(command("cargo", "metadata", "--locked", "--format-version", "1"))
for package in sorted(metadata["packages"], key=lambda item: item["name"]):
    if package["name"] == "slate_lock":
        continue
    directory = Path(package["manifest_path"]).parent
    prefix = f'{package["name"]}-{package["version"]}'
    notices = sorted(
        path for path in directory.iterdir()
        if path.is_file() and path.name.upper().startswith(("LICENSE", "COPYING", "COPYRIGHT"))
    )
    names = []
    for notice in notices:
        name = f"{prefix}/{notice.name}"
        files[name] = notice.read_bytes()
        names.append(name)
    if not notices and package["name"] in ("rustler", "rustler_codegen"):
        name = f"{prefix}/LICENSE-MIT"
        if check:
            files[name] = (destination / name).read_bytes()
        else:
            vcs = json.loads((directory / ".cargo_vcs_info.json").read_text())
            revision = vcs["git"]["sha1"]
            url = f"https://raw.githubusercontent.com/rusterlium/rustler/{revision}/LICENSE-MIT"
            with urlopen(url, timeout=30) as response:
                files[name] = response.read()
        names.append(name)
    if not names:
        raise SystemExit(f"Missing license notices for {prefix}")
    packages.append({
        "name": package["name"],
        "version": package["version"],
        "license": package["license"],
        "notices": names,
    })

rust = destination / "rust" if check else Path(
    command("rustc", "--print", "sysroot").strip()
) / "share/doc/rust"
files["rust/COPYRIGHT-library.html"] = (rust / "COPYRIGHT-library.html").read_bytes()
notices = rust if check else rust / "licenses"
for notice in sorted(notices.iterdir()):
    if notice.is_file():
        files[f"rust/{notice.name}"] = notice.read_bytes()
index = {
    "rust": command("rustc", "--version").strip(),
    "packages": packages,
    "checksums": {name: hashlib.sha256(content).hexdigest() for name, content in files.items()},
}
files["manifest.json"] = (json.dumps(index, indent=2) + "\n").encode()

for name, content in files.items():
    path = destination / name
    if check:
        if not path.is_file() or path.read_bytes() != content:
            raise SystemExit(f"Refresh native license notices: {name}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
