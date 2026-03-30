# Contributing to slate

Thanks for your interest in contributing! This guide will get you up and running.

## Development setup

Tool versions are managed via [asdf](https://asdf-vm.com/) (see `.tool-versions`):

- Erlang 27.2.1
- Gleam 1.14.0
- just 1.38.0

Install dependencies:

```sh
gleam deps download
# or
just deps
```

## Building & testing

| Task | Command |
|------|---------|
| Build | `gleam build` or `just build` |
| Test | `gleam test` or `just test` |
| Type check | `gleam check` or `just check` |
| Format | `gleam format src test` or `just format` |
| Full CI suite | `just ci` |

`just ci` runs format-check → type-check → test → build with `--warnings-as-errors`. Run it before opening a PR.

## Code style

- Format with `gleam format src test` — CI enforces `gleam format --check`.
- All public functions return `Result` types — never raise exceptions.
- Prefer exhaustive pattern matching over catch-all `_` patterns.
- Document public functions with `///` doc comments.

## Testing conventions

Tests use the [startest](https://hexdocs.pm/startest/) framework (not `gleeunit`).

- Name test functions `{module}_{operation}_test` (e.g., `set_insert_lookup_test`).
- Each test creates a temporary `.dets` file with a unique name.
- Call `cleanup(path)` from `test/test_helpers.gleam` at the end of each test to delete the file.
- Use `let assert Ok(...)` for expected-success paths.
- Use `|> expect.to_equal(...)` for specific value checks.

## Changelog entries

PRs require a changelog entry in `.changes/unreleased/`. Create one with:

```sh
just change
```

This wraps [`changie new`](https://changie.dev/) and will prompt you for a kind and description. Available kinds: Added, Breaking, Changed, Deprecated, Fixed, Performance, Removed, Reverted, Dependencies, Security.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/) with lowercase subjects:

```
feat(set): add batch insert support
fix(bag): handle concurrent access correctly
docs: update installation instructions
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

Keep the header to 72 characters or fewer. PR titles must also follow this format — CI checks them with commitlint.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your changes and add tests if applicable.
3. Add a changelog entry (`just change`).
4. Run `just ci` to verify everything passes.
5. Open a PR targeting `main`.

CI must pass (format, type check, build, tests) and a changelog entry is required for feature/fix PRs.
