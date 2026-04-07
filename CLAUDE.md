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
just ci           # Run all CI checks (format, check, test, build)
just pr           # Alias for ci (use before PR)
just main         # Extended checks for main branch
just clean        # Remove build artifacts
```

## Project Structure

```
src/
├── slate.gleam                # Shared types (DetsError, AccessMode, RepairPolicy, TableInfo)
├── dets_ffi.erl              # Erlang FFI for DETS operations
├── with_table_ffi.erl        # Close-on-exit helper used by with_table
└── slate/
    ├── set.gleam             # Set tables (unique keys)
    ├── bag.gleam             # Bag tables (multiple distinct values per key)
    └── duplicate_bag.gleam   # Duplicate bag tables (duplicates allowed)
test/
├── slate_test.gleam            # Test entry point (startest.run)
├── test_helpers.gleam          # Shared test utilities (cleanup, unique paths)
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
└── test_helpers_test.gleam     # Tests for test helpers
```

## Architecture

### Module Organization

- **`slate`**: Shared types — `DetsError`, `AccessMode`, `RepairPolicy`, `TableInfo`
- **`slate/set`**: Set tables — one value per key, `insert` overwrites
- **`slate/bag`**: Bag tables — multiple distinct values per key
- **`slate/duplicate_bag`**: Duplicate bag tables — allows duplicate key-value pairs
- **`dets_ffi.erl`**: Erlang FFI wrapping `dets:*` calls with try-catch error translation
- **`with_table_ffi.erl`**: Erlang helper that closes tables when `with_table` callbacks return or raise

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
- `badarg` → `TableDoesNotExist`
- `DecodeErrors(List(decode.DecodeError))` — returned by read operations when data on disk doesn't match the provided decoders
- Any other error → `ErlangError(formatted_string)`

### Key Design Decisions

- **Module name**: `slate` (not `dets`) to avoid Erlang module name collision
- **Opaque table handles**: `Set(k, v)`, `Bag(k, v)`, `DuplicateBag(k, v)` enforce type safety
- **Bounded table-name pool**: `dets_ffi.erl` reuses a fixed internal pool of DETS table names instead of creating one atom per path
- **`with_table` helper**: Closes when the callback returns and also attempts cleanup if the callback raises; it always uses the default `AutoRepair` + `ReadWrite` open path and is still not crash-proof if the owning process is killed outright

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
- Gleam 1.14.0
- just 1.38.0

## CI/CD

### Workflows
- **ci.yml**: Format check, type check, build, test
- **pr.yml**: PR title validation (commitlint), changelog entry check (changie)
- **release.yml**: Automated versioning via changie-release
- **auto-tag.yml**: Auto-tag on release PR merge
- **publish.yml**: Publish to Hex.pm on tag push

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
