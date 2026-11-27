# Native exclusive-session component

Exclusive sessions need an OS file lock that independent BEAM VMs can see.
OTP has no portable API for one, so this directory holds a small native
library. It uses Rust standard-library `File::try_lock` through Rustler. Unix
targets use `flock`; Windows uses `LockFileEx`.

A lock must not disappear while DETS can still write the file. For this
reason, Erlang process death and resource garbage collection do not release
ownership. The native registry retains each file until explicit release or VM
exit.

Build from a source checkout with:

```sh
just native-build
```

Release CI builds and verifies all five target directories before Hex
publishing. Keep this directory in an Erlang shipment. Escripts need a
`slate_native` companion directory; see the website installation guide.
The registry lives in the loaded module, so do not hot-reload or unload the
native module while sessions or quarantined locks exist.

Native binaries include code from Rust crates and the Rust runtime, so their
notices travel with them. `licenses/THIRD_PARTY_NOTICES.txt` contains full
license texts and attribution
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
