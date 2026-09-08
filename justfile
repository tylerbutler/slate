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

# Build project (Erlang target)
build:
    trellis run build

# Build with warnings as errors
build-strict:
    trellis run build --strict

# === TESTING ===

# Run all tests
test:
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

# Create or update the release PR (requires a clean working tree)
release-pr:
    trellis release pr --base main --branch release/next

# === MAINTENANCE ===

# Remove build artifacts
clean:
    trellis run clean

# === CI ===

# Check workspace and changelog configuration
doctor:
    trellis doctor

# Run all CI checks (doctor, format, check, test, build)
ci: doctor format-check check test build-strict

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs
