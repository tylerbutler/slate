# Development

## Setup

Tool versions are managed with [mise](https://mise.jdx.dev/) (see `.mise.toml`). Install mise, then run:

```sh
mise install
just deps
```

## Just tasks

| Task | Command | Description |
|------|---------|-------------|
| Download dependencies | `just deps` | Download project dependencies |
| Build | `just build` | Build project (Erlang target) |
| Build strict | `just build-strict` | Build with warnings as errors |
| Test | `just test` | Run all tests |
| Format | `just format` | Format source code |
| Format check | `just format-check` | Check formatting without changes |
| Type check | `just check` | Type check without building |
| Docs | `just docs` | Build documentation |
| Changelog entry | `just change` | Create a new changelog entry |
| Changelog preview | `just changelog-preview` | Preview unreleased changelog |
| Changelog merge | `just changelog` | Generate CHANGELOG.md |
| Clean | `just clean` | Remove build artifacts |
| CI | `just ci` | Run all CI checks (format, check, test, build) |
| Main | `just main` | Extended checks for main branch |

`just ci` runs format-check → type-check → test → build with `--warnings-as-errors`. Run it before opening a PR.

## Code style

- Format with `just format` — CI enforces formatting.
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
