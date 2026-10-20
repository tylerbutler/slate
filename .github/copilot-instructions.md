# Copilot Instructions for slate

## Build and Test

```bash
gleam build              # Compile
gleam test               # Run all tests
gleam check              # Type check only
gleam format src test    # Format code
just ci                  # Full CI: doctor, format-check, check, test, strict build
```

Keep `just` for top-level coordination. Its package recipes call Trellis,
configured in `[tools.trellis]` in the root `gleam.toml`. Only the root
`slate` package is a member.

Unitest discovers public test functions with the `_test` suffix. Run one file
with `gleam test -- test/set_test.gleam` or one test with
`gleam test -- --test set_test.set_insert_lookup_test`. Do not edit imports to
select tests. Keep the default sequential execution; tests change VM-wide
state, so do not use `--workers`.

## Architecture

This is a Gleam library (Erlang target only) wrapping Erlang's DETS disk storage. The module is named `slate` instead of `dets` to avoid colliding with Erlang's built-in `dets` module.

### Three table-type modules with a shared API

`slate/set`, `slate/bag`, and `slate/duplicate_bag` each expose an identical public API surface (`open`, `close`, `insert`, `lookup`, `fold`, `with_table`, etc.) but use separate opaque types (`Set(k, v)`, `Bag(k, v)`, `DuplicateBag(k, v)`) to enforce type safety at compile time. The key difference is lookup return types: `set.lookup` returns a single value, while `bag.lookup` and `duplicate_bag.lookup` return `List(v)`.

### FFI layer

All three modules call into a shared Erlang FFI file (`src/slate_dets_ffi.erl`). The FFI translates returned and raised DETS failures into values that match `DetsError` in `src/slate.gleam`. Some error constructors carry context records. When adding a DETS operation, add its Erlang wrapper in `slate_dets_ffi.erl`, then add `@external` bindings in the relevant Gleam modules.

Gleam constructors map to Erlang atoms automatically by convention (e.g., `AutoRepair` → `auto_repair`). The FFI pattern-matches on these atoms.

### Table naming

Slate reuses a bounded pool of 4096 internal DETS table-name atoms. Opening new paths does not create an unbounded number of atoms. If no pool slot is available, open returns `TableNamePoolExhausted`.

`slate_dets_lifetime.erl` keeps path/name reservations through pending opens and
actual DETS process shutdown. A name can disappear from OTP's registry before
the file finishes closing. Preserve path-before-mutation lock order and native
opener ownership. If the lifetime service fails, new opens fail closed until
VM restart; do not erase its marker or restart it with empty state.

## Conventions

- Return `Result` from fallible operations. Pure classifiers can return plain values. Preserve callback exceptions where the API contract requires them.
- Use exhaustive pattern matching; avoid catch-all `_` patterns where practical.
- Document public functions with `///` doc comments.
- Format with `gleam format` (enforced in CI).
- Use `with_table` for short-lived operations. It attempts to close the table when the callback returns or raises; a forced process kill can prevent cleanup.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) with lowercase subjects. Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Max 72 char header.

## Testing patterns

- Tests use `unitest`. The entry point is `test/slate_test.gleam` calling `unitest.main()`.
- Each test creates a temporary `.dets` file with a unique name and calls `cleanup(path)` at the end (from `test/test_helper.gleam`) to delete it.
- Test functions are named `{module}_{operation}_test` (e.g., `set_insert_lookup_test`).
- Assertions use `let assert Ok(...)` for expected-success paths and
  `assert actual == expected` for specific value checks.

## Changelog

Create Trellis TOML entries with `just change <kind> "<body>"`, which calls
`trellis changelog new`. Add entries in `.changes/unreleased/` for user-facing
changes, not contributor-only tooling, CI, or internal documentation changes.
Missing-entry reminders are advisory; invalid fragments fail CI. Preview version bumps
with `just changelog-preview`. Preserve the kind-to-version rules in
`gleam.toml`.

Trellis updates the release PR on `release/next`, batches sections under
`.changes/slate/`, and generates `CHANGELOG.md`. Do not edit the generated
changelog to add entries. Commitlint accepts Trellis's
`release: slate v<version>` titles.
