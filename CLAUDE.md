# slate

## Project Overview

Type-safe Gleam wrapper for Erlang DETS (Disk Erlang Term Storage). Provides persistent key-value storage backed by files on disk, targeting the Erlang (BEAM) runtime.

## Build Commands

```bash
gleam build              # Compile project
gleam test               # Run tests
gleam check              # Type check without building
gleam format src test    # Format code
gleam docs build         # Generate documentation
```

## Just Commands

```bash
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format code
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks (doctor, format, check, test, build)
just pr           # Alias for ci (use before PR)
just main         # Extended checks for main branch
just clean        # Remove build artifacts
just doctor       # Check Trellis workspace and changelog invariants
just changelog-preview # Preview the next version
just release-pr   # Create or update the release PR (clean checkout required)
```

Keep `just` for top-level coordination; its package recipes call Trellis.
Configure Trellis in `[tools.trellis]` in the root `gleam.toml`. The root
`slate` package is the only member; examples keep their separate build scope.

## Project Structure

```
src/
├── slate.gleam                # Shared types (DetsError, AccessMode, RepairPolicy, TableInfo)
├── slate_dets_ffi.erl        # Erlang FFI for DETS operations
├── slate_with_table_ffi.erl  # Close-on-exit helper used by with_table
└── slate/
    ├── set.gleam             # Set tables (unique keys)
    ├── bag.gleam             # Bag tables (multiple distinct values per key)
    └── duplicate_bag.gleam   # Duplicate bag tables (duplicates allowed)
test/
├── slate_test.gleam            # Test entry point (startest.run)
├── test_helper.gleam           # Shared test utilities (cleanup, unique paths)
├── set_test.gleam              # Set table tests
├── bag_test.gleam              # Bag table tests
├── duplicate_bag_test.gleam    # Duplicate bag table tests
├── set_otp_test.gleam          # Set OTP integration tests
├── bag_otp_test.gleam          # Bag OTP integration tests
├── duplicate_bag_otp_test.gleam # Duplicate bag OTP integration tests
├── access_mode_test.gleam      # Read-only access mode tests
├── delete_object_test.gleam    # delete_object tests across table types
├── error_handling_test.gleam   # Error handling and type mismatch tests
├── update_counter_test.gleam   # Atomic counter tests
├── corruption_test.gleam       # Corruption detection and repair tests
├── is_dets_file_test.gleam     # File validation tests
└── test_helper_test.gleam      # Tests for test helpers
```

## Architecture

### Module Organization

- **`slate`**: Shared types — `DetsError`, `AccessMode`, `RepairPolicy`, `TableInfo`
- **`slate/set`**: Set tables — one value per key, `insert` overwrites
- **`slate/bag`**: Bag tables — multiple distinct values per key
- **`slate/duplicate_bag`**: Duplicate bag tables — allows duplicate key-value pairs
- **`slate_dets_ffi.erl`**: Erlang FFI wrapping `dets:*` calls with try-catch error translation
- **`slate_with_table_ffi.erl`**: Erlang helper that closes tables when `with_table` callbacks return or raise

### FFI Pattern

Gleam `RepairPolicy` constructors map directly to Erlang atoms:
- `AutoRepair` → `auto_repair` → `{repair, true}`
- `ForceRepair` → `force_repair` → `{repair, force}`
- `NoRepair` → `no_repair` → `{repair, false}`

DETS error atoms map back to Gleam `DetsError` constructors:
- `not_found` → `NotFound`
- `key_already_present` → `KeyAlreadyPresent`
- `{file_error, _, enoent}` → `FileNotFound`
- `{file_error, _, eacces}` / `{file_error, _, {error, eacces}}` / `{file_error, _, {error, einval}}` / `{access_mode, _}` → `AccessDenied`
- `{type_mismatch, _}` / `{keypos_mismatch, _}` → `TypeMismatch`
- `{incompatible_arguments, _}` / `incompatible_arguments` → `AlreadyOpen`
- `{file_error, _, efbig}` → `FileSizeLimitExceeded`
- `badarg` / `{no_such_table, _}` → `TableDoesNotExist`
- `{not_a_dets_file, _}` → `NotADetsFile`
- `{needs_repair, _}` → `NeedsRepair`
- `DecodeErrors(List(decode.DecodeError))` — returned by read operations when data on disk doesn't match the provided decoders
- Any other error → `UnexpectedError(formatted_string)`

### Key Design Decisions

- **Module name**: `slate` (not `dets`) to avoid Erlang module name collision
- **Opaque table handles**: `Set(k, v)`, `Bag(k, v)`, `DuplicateBag(k, v)` enforce type safety
- **Bounded table-name pool**: `slate_dets_ffi.erl` reuses a fixed internal pool of DETS table names instead of creating one atom per path
- **`with_table` helper**: Requires explicit repair and access options. Closes when the callback returns and attempts cleanup if the callback raises, but cannot close the table if the owning process is killed outright

## Dependencies

### Runtime
- `gleam_stdlib` - Standard library
- `gleam_erlang` - Erlang interop

### Development
- `startest` - Testing framework

## Testing

```bash
just test
# or
gleam test
```

Tests create temporary `.dets` files and clean them up after each test.

## Tool Versions

Managed via `.tool-versions` (source of truth for CI):
- Erlang 27.2.1
- Gleam 1.18.1
- just 1.38.0
- Trellis: `github:tylerbutler/trellis` in `.tool-versions`, also pinned in `.mise.toml`

## CI/CD

### Workflows
- **ci.yml**: Trellis doctor, format check, type check, build, test, docs
- **pr.yml**: PR title validation (commitlint), Trellis changelog check and preview
- **release.yml**: Trellis versioning and release PR on `release/next`
  - Trellis titles use `release: slate v<version>`; commitlint accepts `release`.
- **auto-tag.yml**: Trellis tags the release PR's merge commit as `v<version>`
- **publish.yml**: Run CI, then use Trellis for the GitHub Release and Hex publish

### Changelog

Run `just change <kind> "<body>"` to create a Trellis TOML fragment in
`.changes/unreleased/` for user-facing changes. Omit entries for contributor-only
tooling, CI, and internal documentation changes. Missing-entry reminders are
advisory; invalid fragments fail CI. Keep the existing kind-to-version rules in
`gleam.toml`: Breaking is major, Added is minor, and the other kinds are patch.
Trellis generates `CHANGELOG.md` from `.changes/slate/v<version>.md`; do not
edit the generated file to add entries.

## Conventions

- Use Result types over exceptions
- Exhaustive pattern matching
- Follow `gleam format` output
- Keep public API minimal
- Document public functions with `///` comments

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(set): add batch insert support
fix(bag): handle concurrent access correctly
docs: update installation instructions
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

## DETS Limitations

- **2 GB maximum file size** per table
- **No `ordered_set`** table type (unlike ETS)
- **Disk I/O** on every operation — not suitable for high-frequency reads
- **Tables must be closed properly** — `with_table` closes on callback return and attempts cleanup on callback failure, but abrupt process exits can still leave DETS needing repair
- **Bounded table-name pool** — slate avoids unbounded atom growth, but only a bounded number of distinct tables can be open at once

## Design Context

The `website/` docs site (Astro Starlight, deployed to slate.tylerbutler.com) has captured design context:

- **PRODUCT.md** (repo root) — strategic context: product register, docs-first, broader-BEAM-developer audience, "gap-filler" positioning, anti-references, WCAG AA baseline.
- **DESIGN.md** (repo root) — visual system: the "Slate Ledger" blue-gray tonal palette, Schibsted Grotesk + Spline Sans Mono typography, flat/tonal elevation, named rules.

Read both before doing any design or content work on `website/`.
