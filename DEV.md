# Development

## Setup

Tool versions are managed with [mise](https://mise.jdx.dev/) (see `.mise.toml`). Install mise, then run:

```sh
mise install
just deps
just native-build
just native-license-tools
```

Exclusive-session source builds require Rust/Cargo 1.91. The native crate pins
its toolchain in `priv/slate_lock/source/rust-toolchain.toml`. Cargo downloads
Rustler and OS interop dependencies from the locked manifest. You do not need
Elixir or a shell `flock` utility.

Use `just` for top-level coordination. Its package recipes call
[Trellis](https://trellis.tylerbutler.com/). Configure Trellis in
`gleam.toml` under `[tools.trellis]`. Only the root `slate` package is a
member; `examples/dotes` keeps its separate build and release scope.
Pin Gleam and Trellis to the same versions in `.mise.toml` and `.tool-versions`.
CI reads the latter through `.github/actions/setup` and
`.github/actions/setup-trellis`.

## Just tasks

| Task | Command | Description |
|------|---------|-------------|
| Download dependencies | `just deps` | Download project dependencies |
| Build | `just build` | Build project (Erlang target) |
| Build strict | `just build-strict` | Build with warnings as errors |
| Native build | `just native-build` | Build the current supported target into `priv/slate_lock/` |
| Native check | `just native-check` | Check Rust formatting, clippy, and native unit tests |
| Notice tools | `just native-license-tools` | Install the pinned cargo-about generator |
| Refresh notices | `just native-licenses` | Generate crate notices and update their manifest |
| Check notices | `just native-licenses-check` | Run notice tests and check for drift without writing files |
| Native package proof | `just native-package-check [archive]` | Load from an extracted Hex package, shipment, and relocated escript |
| Native release check | `just native-release-check` | Require all five prebuilt artifacts |
| Test | `just test` | Run all tests |
| Format | `just format` | Format source code |
| Format check | `just format-check` | Check formatting without changes |
| Type check | `just check` | Type check without building |
| Docs | `just docs` | Build documentation |
| Changelog entry | `just change Fixed "Fixed a lookup error."` | Create a Trellis TOML fragment |
| Changelog preview | `just changelog-preview` | Preview the next version without writing files |
| Release PR | `just release-pr` | Batch entries and create or update the release PR |
| Clean | `just clean` | Remove build artifacts |
| Workspace health | `just doctor` | Check Trellis configuration and changelog fragments |
| CI | `just ci` | Run all CI checks (doctor, format, check, test, build) |
| Main | `just main` | Extended checks for main branch |

`just test` builds the native component before tests. `just ci` also checks
native formatting, clippy, and license notices. Run it before opening a PR.
`gleam test` needs an existing native artifact for exclusive-session tests.

`src/slate/internal/exclusive_session.gleam` implements the session protocol
with typed `gleam_erlang` subjects and monitors. The Erlang bridges retain
DETS inspection, diagnostics, and exception capture with the original stack.
Successful callback values stay in the calling process.

Crate notices are generated with cargo-about from the complete locked graph,
including build dependencies, procedural macros, and dependencies outside
release targets. MIT is selected where the upstream license permits it.
The generator preserves full license texts and supplemental copyright notices
in `priv/slate_lock/licenses/THIRD_PARTY_NOTICES.txt`. Rust runtime notices
remain separate under `licenses/rust/`; cargo-about does not collect them.

After changing native dependencies, run `just native-licenses` and review the
output before committing it. Licensing warnings and unresolved upstream texts
fail generation instead of falling back to generic notices.
A Rust toolchain change requires a separate review
and `python priv/slate_lock/source/collect_licenses.py --refresh-rust`.
Normal builds and Hex consumers do not need cargo-about.
Notice refresh removes obsolete files from the generated `licenses/`
directory. Check mode rejects extra files without changing them.

## Code style

- Format with `just format` — CI enforces formatting.
- All public functions return `Result` types — never raise exceptions.
- Prefer exhaustive pattern matching over catch-all `_` patterns.
- Document public functions with `///` doc comments.

## Testing conventions

Tests use the [startest](https://hexdocs.pm/startest/) framework (not `gleeunit`).

- Name test functions `{module}_{operation}_test` (e.g., `set_insert_lookup_test`).
- Each test creates a temporary `.dets` file with a unique name.
- Call `cleanup(path)` from `test/test_helper.gleam` at the end of each test to delete the file.
- Use `let assert Ok(...)` for expected-success paths.
- Use `|> expect.to_equal(...)` for specific value checks.

Run a file group with `gleam test -- exclusive` or filter a test name with
`gleam test -- --test-name-filter=exclusive`. Do not edit test imports to select
tests. Exclusive tests launch independent BEAM VMs and use a bounded message
protocol. Delete their sidecars only after all child VMs stop.
Linux native CI also runs mounted-file regressions inside a private mount
namespace. These tests need mount privileges and do not run in the default
Cargo test group.

## Changelog entries

Add a TOML changelog entry in `.changes/unreleased/` for changes that affect
library users. Omit entries for contributor-only tooling, CI, and internal
documentation changes. Create an entry with:

```sh
just change Fixed "Fixed a lookup error."
# Equivalent:
trellis changelog new --kind Fixed --body "Fixed a lookup error."
```

Pass the kind and body as arguments; there is no prompt. Use the first line
of the body as the entry title, then add a blank line before any details.
Available kinds: Added, Breaking, Changed, Deprecated, Fixed, Performance,
Removed, Reverted, Dependencies, Security. Breaking implies a major bump;
Added implies a minor bump; the other kinds imply a patch bump.

Run `just changelog-preview` to see the next version. To preview this branch's
changelog sections and check for missing entries, run:

```sh
trellis changelog check --base origin/main
```

The PR workflow keeps the previous advisory policy: it comments about missing
entries for `feat`, `fix`, `refactor`, `security`, or breaking-change commits.
Missing entries do not fail CI; invalid fragments do. Reviewers decide whether
a change needs release notes. The release PR is exempt because it consumes
entries instead of adding them.

### Release flow

On a push to `main`, CI runs `trellis release pr --base main --branch release/next`.
Trellis updates the release PR with the version in `gleam.toml`, new sections
in `.changes/slate/`, and the generated `CHANGELOG.md`. It removes the
fragments it has consumed.

Merge that PR to create a `v<version>` tag at the merge commit. The tag push
starts CI, then Trellis creates the GitHub Release from the matching changelog
section and publishes to Hex. The workflows use `RELEASE_APP_ID` and
`RELEASE_APP_PRIVATE_KEY` for PR and tag events, and `HEXPM_API_KEY` for Hex.

CI builds and runs native/session/package proofs on Linux glibc x64 and ARM64,
macOS x64 and ARM64, and Windows x64. The publish job collects those artifacts
from the same workflow run and checks the complete set before Hex packaging.
CI also builds a complete Hex archive on Linux and runs its consumer, shipment,
and relocated-escript proofs on Windows.
Use `just native-package-check path/to/slate-version.tar` to check an existing
archive without exporting one.
Linux builds use Ubuntu 22.04 (glibc 2.35); macOS builds use a 15.0 deployment
target; Windows builds use MSVC on Server 2022. Do not publish native artifacts
from a different revision or bypass a failed target. Missing runners or failed
platform proofs block release.

To update the release PR from a clean local checkout, run `just release-pr`.
It pushes the release branch and requires GitHub authentication. The old
`just changelog` merge-only recipe has no Trellis equivalent; use the release
PR flow to generate the changelog and bump the version together.

Do not edit `CHANGELOG.md` to add entries. Trellis regenerates it from
`.changes/slate/v<version>.md`. The migration preserves the published sections
and pending entry text from Changie.

## Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/) with lowercase subjects:

```
feat(set): add batch insert support
fix(bag): handle concurrent access correctly
docs: update installation instructions
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

Trellis uses `release: slate v<version>` for release commits and PR titles.
Commitlint accepts the `release` type for this flow.

Keep the header to 72 characters or fewer. PR titles must also follow this format — CI checks them with commitlint.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your changes and add tests if applicable.
3. Add a changelog entry for user-facing changes (`just change <kind> "<body>"`).
4. Run `just ci` to verify everything passes.
5. Open a PR targeting `main`.

CI must pass (doctor, format, type check, build, tests).
