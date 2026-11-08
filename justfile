# Gleam Project Tasks

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias d := docs
alias cl := change

default:
    @just --list

# === DEPENDENCIES ===

# Download project dependencies
deps:
    trellis run deps

# === BUILD ===

# Build the native component used by exclusive table sessions
native-build:
    escript priv/slate_lock/source/build.escript

# Check the pinned native source
native-check:
    cd priv/slate_lock/source && cargo fmt --check && cargo clippy --locked --all-targets --target-dir ../../../build/native -- -D warnings && cargo test --locked --target-dir ../../../build/native

# Install the pinned notice generator with the native crate's Rust toolchain
native-license-tools:
    cd priv/slate_lock/source && cargo install --locked --version 0.9.2 --features cli cargo-about

# Refresh crate notices and the native notice manifest
native-licenses:
    python priv/slate_lock/source/collect_licenses.py

# Check native notice generation without changing committed files
native-licenses-check:
    python test/support/collect_licenses_test.py
    python priv/slate_lock/source/collect_licenses.py --check

# Prove Hex, shipment, and relocated escript native loading
[positional-arguments]
native-package-check archive="":
    if [ -n "$1" ]; then escript test/support/exclusive-package.escript --archive "$1"; else escript test/support/exclusive-package.escript; fi

# Require every release artifact before publishing
native-release-check:
    escript test/support/exclusive-package.escript --release-artifacts

# Build project (Erlang target)
build: sbom-clean && sbom
    trellis run build

# Build with warnings as errors
build-strict: sbom-clean && sbom
    trellis run build --strict

# Generate separate Gleam and native Rust dependency inventories
sbom: sbom-clean
    mkdir -p build/sbom
    licence_audit sbom --reproducible --output=build/sbom/slate-gleam.cdx.json
    syft scan dir:priv/slate_lock/source --output cyclonedx-json@1.6=build/sbom/slate-native.cdx.json

# Remove local inventories before compilation or generation
[private]
sbom-clean:
    rm -f build/sbom/slate-gleam.cdx.json build/sbom/slate-native.cdx.json

# Check generated inventories against the checked-out lockfiles
sbom-check:
    node --test test/support/sbom_test.cjs test/support/sbom_commands_test.cjs

# === TESTING ===

# Run all tests
test: native-build
    trellis run test

# === CODE QUALITY ===

# Format source code
format:
    trellis run format

# Check formatting without changes
format-check:
    trellis run format --check

# Type check without building
check:
    trellis run check

# === DOCUMENTATION ===

# Build documentation
docs:
    trellis run docs

# === CHANGELOG ===

# Create a new changelog entry
[positional-arguments]
change kind body:
    trellis changelog new --kind "$1" --body "$2"

# Preview unreleased changelog
changelog-preview:
    trellis version plan

# Request coordinated release preparation on main
[positional-arguments]
release-pr pre="" version="" replace="false":
    gh workflow run release.yml --ref main -f operation=prepare -f pre="$1" -f version="$2" -f replace="$3"

# Recover a merged release at its original revision
[positional-arguments]
release-recover pr:
    gh workflow run release.yml --ref main -f operation=recover -f pr_number="$1"

# Check release selection, arguments, and workflow dependencies without remote writes
release-check:
    node --test test/support/release_test.cjs

# Exercise the pinned native CLI against disposable Git and a loopback GitHub stub
release-cli-check:
    node --test test/support/release_cli_test.cjs

# === MAINTENANCE ===

# Remove build artifacts
clean:
    trellis run clean

# === CI ===

# Check workspace and changelog configuration
doctor:
    trellis doctor

# Run all CI checks (doctor, format, check, test, build)
ci: doctor release-check release-cli-check format-check check native-check native-licenses-check test build-strict sbom-check

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs
