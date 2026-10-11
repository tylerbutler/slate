"""Generate crate notices with cargo-about and preserve Rust runtime notices."""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
DESTINATION = SOURCE.parent / "licenses"


def command(*args):
    generating = args[:3] == ("cargo", "about", "generate")
    if generating:
        args = args[:2] + ("--color", "never") + args[2:]
    try:
        result = subprocess.run(args, cwd=SOURCE, text=True, encoding="utf-8",
                                capture_output=True)
    except FileNotFoundError as error:
        raise SystemExit(f"Missing tool {args[0]}: run just native-license-tools.") from error
    diagnostics = re.sub(r"\x1b\[[0-9;]*m", "", result.stderr)
    sys.stderr.write(diagnostics)
    result.check_returncode()
    # --fail still permits fallback after a failed clarification.
    if generating and "[WARN]" in diagnostics:
        raise SystemExit("cargo-about reported licensing warnings; resolve them before generating notices.")
    return result.stdout


def crate_notices(metadata, report, rendered):
    expected = {
        (package["name"], package["version"]): package
        for package in metadata["packages"] if package["name"] != "slate_lock"
    }
    selected = {}
    for license in report["licenses"]:
        if not license["source_path"]:
            raise SystemExit(f"Missing upstream license text: {license['id']}")
        if license["text"].strip() not in rendered:
            raise SystemExit(f"Missing rendered license text: {license['id']}")
        for entry in license["used_by"]:
            package = entry["crate"]
            key = (package["name"], package["version"])
            if f"- {key[0]} {key[1]}\n" not in rendered:
                raise SystemExit(f"Missing rendered crate attribution: {key}")
            selected.setdefault(key, set()).add(license["id"])
    if set(selected) != set(expected):
        raise SystemExit(
            f"License coverage mismatch: missing={sorted(set(expected) - set(selected))}, "
            f"extra={sorted(set(selected) - set(expected))}"
        )

    packages = []
    additions = []
    for key, package in sorted(expected.items()):
        directory = Path(package["manifest_path"]).parent
        notices = sorted(
            path for path in directory.iterdir()
            if path.is_file() and path.name.upper().startswith(("COPYRIGHT", "NOTICE"))
        )
        for notice in notices:
            additions.append(
                f"\n{key[0]} {key[1]} / {notice.name}\n"
                "----------------------------------------------------\n"
                + notice.read_text(encoding="utf-8").rstrip() + "\n"
            )
        packages.append({
            "name": key[0],
            "version": key[1],
            "license": package["license"],
            "selected": sorted(selected[key]),
            "attribution": [notice.name for notice in notices],
        })
    if additions:
        rendered += "\nAdditional upstream attribution\n" + "".join(additions)
    return rendered.encode("utf-8"), packages


def runtime_files(destination, rust_version, refresh):
    if refresh:
        rust = Path(command("rustc", "--print", "sysroot").strip()) / "share/doc/rust"
        files = {"rust/COPYRIGHT-library.html": (rust / "COPYRIGHT-library.html").read_bytes()}
        files.update({
            f"rust/{notice.name}": notice.read_bytes()
            for notice in sorted((rust / "licenses").iterdir()) if notice.is_file()
        })
        return files

    index = json.loads((destination / "manifest.json").read_text(encoding="utf-8"))
    if index["rust"] != rust_version:
        raise SystemExit("Rust toolchain changed: review and run collect_licenses.py --refresh-rust.")
    files = {}
    for name, checksum in sorted(index["checksums"].items()):
        if name.startswith("rust/"):
            content = (destination / name).read_bytes()
            if hashlib.sha256(content).hexdigest() != checksum:
                raise SystemExit(f"Changed Rust runtime notice: {name}")
            files[name] = content
    if not files or "rust/COPYRIGHT-library.html" not in files:
        raise SystemExit("Missing Rust runtime notice bundle.")
    return files


def generate(destination=DESTINATION, refresh_rust=False):
    metadata = json.loads(command("cargo", "metadata", "--locked", "--format-version", "1"))
    args = ("cargo", "about", "generate", "--locked", "--fail")
    report = json.loads(command(*args, "--format", "json"))
    rendered = command(*args, "about.hbs")
    notice, packages = crate_notices(metadata, report, rendered)
    rust_version = command("rustc", "--version").strip()
    files = {"THIRD_PARTY_NOTICES.txt": notice}
    files.update(runtime_files(destination, rust_version, refresh_rust))
    index = {
        "generator": command("cargo", "about", "--version").strip(),
        "rust": rust_version,
        "packages": packages,
        "checksums": {name: hashlib.sha256(content).hexdigest() for name, content in files.items()},
    }
    files["manifest.json"] = (json.dumps(index, indent=2) + "\n").encode("utf-8")
    return files


def write_or_check(files, destination, check):
    for name, content in files.items():
        path = destination / name
        if check:
            if not path.is_file() or path.read_bytes() != content:
                raise SystemExit(f"Refresh native license notices: {name}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)


def main():
    args = sys.argv[1:]
    if args not in ([], ["--check"], ["--refresh-rust"]):
        raise SystemExit("Usage: collect_licenses.py [--check | --refresh-rust]")
    files = generate(refresh_rust=args == ["--refresh-rust"])
    write_or_check(files, DESTINATION, args == ["--check"])


if __name__ == "__main__":
    main()
