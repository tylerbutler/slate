# Native exclusive-session component

Slate uses Rust standard-library `File::try_lock` with Rustler. Unix targets
use `flock`; Windows uses `LockFileEx`. Erlang process death and resource
garbage collection do not release ownership. The native registry retains
each file until explicit release or VM exit.

Build from a source checkout with:

```sh
just native-build
```

Release CI builds and verifies all five target directories before Hex
publishing. Keep this directory in an Erlang shipment. Escripts need a
`slate_native` companion directory; see the website installation guide.
Do not hot-reload or unload the native module while sessions or quarantined
locks exist.

`licenses/THIRD_PARTY_NOTICES.txt` contains full license texts and attribution
for the complete locked Cargo graph. Pinned cargo-about tooling generates it
with MIT selected where permitted. `licenses/rust/` contains the separate
Rust standard-library and runtime notices. Slate's MIT license remains in the
repository root. Copy the complete `licenses/` directory with native binaries.

Run `just native-license-tools` to install the generator. After updating native
dependencies, run `just native-licenses` and review and commit the output.
`just native-licenses-check` runs regression tests and checks for drift without
writing files. After a Rust toolchain change, review and refresh its runtime
notices with `python priv/slate_lock/source/collect_licenses.py --refresh-rust`.
Refresh removes obsolete generated notices; checks reject extra files.
Normal native builds do not need the notice generator.
