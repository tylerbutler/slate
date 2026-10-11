---
title: Installation
description: How to install slate in your Gleam project.
---

Add slate to your Gleam project:

```bash
gleam add slate
```

This adds slate to your `gleam.toml` dependencies. slate supports Gleam's Erlang target, which runs on the BEAM. It does not support the JavaScript target.

## Requirements

- **Gleam** >= 1.7.0
- **Erlang/OTP** >= 26 (recommended: 27+)
- **Target**: Erlang only

## Dependencies

Gleam also installs these packages:

| Package | Purpose |
|---------|---------|
| `gleam_stdlib` | Standard library |
| `gleam_erlang` | Erlang interoperability |

## Exclusive-session native component

Hex releases include the native files for these targets:

| OS | Architecture | Baseline | Allowed filesystems |
|----|--------------|----------|---------------------|
| Linux | x64, ARM64 | glibc 2.35+, kernel 5.8+ | Local ext2/3/4, tmpfs |
| macOS | x64, ARM64 | macOS 15+ | Local APFS |
| Windows | x64 | Windows Server 2022 / Windows 10+ with the MSVC runtime | Fixed-drive NTFS |

The native component uses Rust standard-library locks through Rustler. It
requires NIF ABI 2.17 (OTP 26+). Unlocked APIs do not load it. Unsupported
platforms or filesystems return typed acquisition errors; Slate does not open
the table without a lock. Musl Linux, network mounts, FUSE, overlay filesystems,
and other unqualified types are unsupported.

Use a local filesystem on one host. Sharing a network volume or a sidecar
between hosts does not extend the support contract. Keep the data directory
trusted and stable, and keep the sidecar beside the data file. tmpfs loses its
contents on host restart; use persistent storage for data you must retain.
On Linux, mount the containing directory rather than individual data or
sidecar files. Slate requires kernel mount-identity metadata and rejects
file mount points, including bind-mounted files.

### Source checkouts

Install Rust/Cargo 1.91 with your native linker, then run:

```sh
just native-build
```

The crate pins its Rust toolchain and dependencies under
`priv/slate_lock/source/`. The build copies the native library to
`priv/slate_lock/<target>/`. If you use an extracted Hex source package instead
of a checkout, run `escript priv/slate_lock/source/build.escript`.
Source builds need no Elixir runtime. Normal Hex consumers need no Rust compiler
and do not download native code at runtime.

### Erlang shipments and escripts

`gleam export erlang-shipment` copies the application's `priv` directory.
Keep it in the shipment when you move or deploy the application.

`gleam export escript` does **not** include native files. Copy the target's
library from Slate's `priv/slate_lock/<target>/` and the native `licenses/`
directory to a companion directory:

```text
my-cli
slate_native/
  x86_64-linux-gnu/
    slate_lock.so
  licenses/
    THIRD_PARTY_NOTICES.txt
    manifest.json
    rust/
      ...
```

Copy the complete `licenses/` directory. The crate notice file contains full
license texts and attribution; the `rust/` directory contains separate Rust
runtime notices.

Use `slate_lock.so` for Linux/macOS or `slate_lock.dll` for Windows. For a CLI
that runs on more than one target, include each target directory. Slate finds
`slate_native` beside the script, independent of the current working directory.
Keep the script and companion directory together when you relocate them.
A missing or incompatible library returns `NativeUnavailable`; unlocked APIs
remain usable.

Release CI must pass independent-VM and package-loading proofs on all five
targets before publishing. See [exclusive sessions](/advanced/exclusive-sessions/)
for the ownership and path requirements.

## Upgrading

See the [changelog](https://github.com/tylerbutler/slate/blob/main/CHANGELOG.md) for release history and breaking changes. See [Stability and versioning](/advanced/stability/) for the versioning policy.
