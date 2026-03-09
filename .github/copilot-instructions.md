# Copilot Instructions for slate

## Build and Test

```bash
gleam build              # Compile
gleam test               # Run all tests
gleam check              # Type check only
gleam format src test    # Format code
just ci                  # Full CI: format-check, check, test, build --warnings-as-errors
```

Gleam's test runner (`startest`) discovers test functions by the `_test` suffix — there is no built-in way to run a single test. To run one test file, temporarily comment out other imports or isolate the file.

## Architecture

This is a Gleam library (Erlang target only) wrapping Erlang's DETS disk storage. The module is named `slate` instead of `dets` to avoid colliding with Erlang's built-in `dets` module.

### Three table-type modules with a shared API

`slate/set`, `slate/bag`, and `slate/duplicate_bag` each expose an identical public API surface (`open`, `close`, `insert`, `lookup`, `fold`, `with_table`, etc.) but use separate opaque types (`Set(k, v)`, `Bag(k, v)`, `DuplicateBag(k, v)`) to enforce type safety at compile time. The key difference is lookup return types: `set.lookup` returns a single value, while `bag.lookup` and `duplicate_bag.lookup` return `List(v)`.

### FFI layer

All three modules call into a single Erlang FFI file (`src/dets_ffi.erl`). The FFI wraps every `dets:*` call in try-catch and translates Erlang error tuples into atoms that map to the `DetsError` Gleam type in `src/slate.gleam`. When adding new DETS operations, add the Erlang wrapper in `dets_ffi.erl`, then add `@external` bindings in the relevant Gleam module(s).

Gleam constructors map to Erlang atoms automatically by convention (e.g., `AutoRepair` → `auto_repair`). The FFI pattern-matches on these atoms.

### Table naming

DETS table names are the file path converted to an Erlang atom via `binary_to_atom/2`. Each unique path permanently consumes an atom.

## Conventions

- All public functions return `Result` types — never raise exceptions.
- Use exhaustive pattern matching; avoid catch-all `_` patterns where practical.
- Document public functions with `///` doc comments.
- Format with `gleam format` (enforced in CI).
- Use `with_table` for short-lived operations to guarantee the table is closed.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) with lowercase subjects. Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Max 72 char header.

## Testing patterns

- Tests use `startest` (not `gleeunit`). The entry point is `test/slate_test.gleam` calling `startest.run()`.
- Each test creates a temporary `.dets` file with a unique name and calls `cleanup(path)` at the end (from `test/test_helpers.gleam`) to delete it.
- Test functions are named `{module}_{operation}_test` (e.g., `set_insert_lookup_test`).
- Assertions use `let assert Ok(...)` for expected-success paths and `|> expect.to_equal(...)` for specific value checks.

## Changelog

New changes require a changelog entry via `changie new` (aliased as `just change`). CI checks for a `.changes/unreleased/` entry on PRs.
