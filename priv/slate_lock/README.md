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

`licenses/` contains notices for the Rust standard library and locked native
dependencies. Slate's MIT license remains in the repository root.
After updating native dependencies or the pinned Rust toolchain, run
`python priv/slate_lock/source/collect_licenses.py` and commit the resulting
notices. CI checks them with `--check`.
