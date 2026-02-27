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
├── slate.gleam            # Shared types (DetsError, Kind, RepairPolicy, TableInfo)
├── dets_ffi.erl                # Erlang FFI for DETS operations
└── slate/
    ├── set.gleam               # Set tables (unique keys)
    ├── bag.gleam               # Bag tables (multiple distinct values per key)
    └── duplicate_bag.gleam     # Duplicate bag tables (duplicates allowed)
test/
├── slate_test.gleam       # Test entry point
├── set_test.gleam              # Set table tests
├── bag_test.gleam              # Bag table tests
└── duplicate_bag_test.gleam    # Duplicate bag table tests
```

## Architecture

### Module Organization

- **`slate`**: Shared types — `DetsError`, `Kind`, `RepairPolicy`, `TableInfo`
- **`slate/set`**: Set tables — one value per key, `insert` overwrites
- **`slate/bag`**: Bag tables — multiple distinct values per key
- **`slate/duplicate_bag`**: Duplicate bag tables — allows duplicate key-value pairs
- **`dets_ffi.erl`**: Erlang FFI wrapping `dets:*` calls with try-catch error translation

### FFI Pattern

Gleam `RepairPolicy` constructors map directly to Erlang atoms:
- `AutoRepair` → `auto_repair` → `{repair, true}`
- `ForceRepair` → `force_repair` → `{repair, force}`
- `NoRepair` → `no_repair` → `{repair, false}`

DETS error atoms map back to Gleam `DetsError` constructors:
- `not_found` → `NotFound`
- `key_already_present` → `KeyAlreadyPresent`
- `{erlang_error, Msg}` → `ErlangError(msg)`

### Key Design Decisions

- **Module name**: `slate` (not `dets`) to avoid Erlang module name collision
- **Opaque table handles**: `Set(k, v)`, `Bag(k, v)`, `DuplicateBag(k, v)` enforce type safety
- **Table name = path atom**: DETS table names are derived from the file path converted to an atom
- **`with_table` helper**: Ensures tables are closed even if the callback fails

## Dependencies

### Runtime
- `gleam_stdlib` - Standard library
- `gleam_erlang` - Erlang interop

### Development
- `gleeunit` - Testing framework

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
- **Tables must be closed properly** — use `with_table` for safety
- **Atom exhaustion risk** — each unique path creates an atom for the table name
