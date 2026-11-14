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
`gleam.toml` under `[tools.trellis]`. Register `slate` and `examples/dotes`
as members so Trellis updates the example's local dependency lockfile.
Exclude `examples/dotes` only from releases; normal workspace tasks include it.
Keep tool versions in `.mise.toml` for both local setup and CI.
The shared `.github/actions/setup-mise` action installs and caches these tools.
CI and publish jobs install all configured tools; PR and release jobs install
only Node.js or Trellis as needed.

Rebar3 builds the Erlang HTTP dependencies in `examples/dotes`. The mise
configuration includes it so a clean example build does not depend on a
previously compiled dependency cache.

## Agent configuration

Edit project skills in `.apm/skills/<name>/SKILL.md` and agent definitions in
`.apm/agents/<name>.agent.md`. Shared skills and agents come from the
dependencies in `apm.yml`; do not copy those sources into `.apm/`.

Run `apm install --frozen` to install the locked dependencies and deploy the
project definitions to the Claude and Copilot targets in `apm.yml`.
APM writes skills to `.claude/skills/` and `.agents/skills/`, and agents to
`.claude/agents/` and `.github/agents/`. Commit the generated files and
`apm.lock.yaml` with source changes. Do not edit the generated copies.

## Just tasks

| Task | Command | Description |
|------|---------|-------------|
| Download dependencies | `just deps` | Download project dependencies |
| Build | `just build` | Build project and generate SBOMs |
| Build strict | `just build-strict` | Build with warnings as errors and generate SBOMs |
| SBOM | `just sbom` | Generate separate Gleam and Rust CycloneDX inventories |
| SBOM check | `just sbom-check` | Compare generated inventories with the checked-out lockfiles |
| SBOM package check | `just sbom-package-check path/to/slate-version.tar` | Compare packaged SBOM bytes with the qualified documents |
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
| Licence report | `just audit-licences` | Report locked Gleam dependency licences against the policy |
| Vulnerability report | `just audit-vulns` | Report known vulnerabilities through OSV.dev |
| Audit check | `just audit-check` | Enforce the licence policy and vulnerability threshold |
| Docs | `just docs` | Build documentation |
| Changelog entry | `just change Fixed "Fixed a lookup error."` | Create a Trellis TOML fragment |
| Changelog preview | `just changelog-preview` | Preview the next version without writing files |
| Release PR | `just release-pr [pre] [version] [replace]` | Request coordinated preparation on main |
| Release recovery | `just release-recover <pr-number>` | Recover publication at a merged release PR's revision |
| Release checks | `just release-check` | Check release coordination without remote writes |
| Native CLI checks | `just release-cli-check` | Exercise the pinned Trellis against local Git and a loopback API |
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

`src/slate_dets_lifetime.erl` tracks path/name reservations, pending opens, and
actual DETS process lifetimes. OTP can remove a table name before its final close
finishes, so absence from `dets:all()` does not mean the file is safe to reopen.
The FFI keeps native opens in the caller and uses path-before-mutation lock order
for explicit closes.

The lifetime service starts as a temporary child of `kernel_safe_sup`. One fixed
`persistent_term` marker prevents an empty-state restart after service failure.
New opens then fail with `UnexpectedError`; existing reads and cleanup closes
remain available. Recover by restarting the VM, not by erasing the marker or
restarting DETS internals. Start a fresh VM when adopting this implementation
from older code with active tables. This node-local service does not replace
exclusive sessions for access from independent VMs.

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

## Dependency audits

Use the mise-pinned native licence_audit 1.0.0-rc.2 for local audits and SBOM
generation. This prerelease includes its own Erlang runtime and leaves Slate's
OTP version and Gleam dependencies unchanged.

Run `just audit-licences` to preview the `[tools.licence_audit]` policy in
`gleam.toml`, or `just audit-vulns` to query OSV.dev. These reports do not fail
on findings. Run `just audit-check` to enforce both the licence policy and the
default vulnerability threshold (high; unknown severity does not block).
Network or input failures return a non-zero exit code.

These tasks cover the root `manifest.toml`, including development dependencies.
They do not scan the dotes example, Rust crates, or website packages. OSV queries
require network access; licence reports can reuse cached Hex metadata.
The existing policy allows Apache-2.0 and MIT. It does not approve BSD-3-Clause
for `tobble` and `string_width`, so the check fails until a maintainer resolves
those findings. This setup leaves policy and CI enforcement unchanged.

## Website

The Astro/Starlight website uses Cloudflare Workers Static Assets. It builds
static files without an Astro adapter or Worker script. Use Node.js 22.12+
and the pnpm version in `website/package.json`.

Keep `@astrojs/markdown-remark` installed and use its `unified()` processor in
`website/astro.config.mjs` to run the site's emoji accessibility plugin.

```sh
cd website
pnpm install --frozen-lockfile
pnpm build
pnpm exec wrangler dev
```

`pnpm preview` serves the Astro build. `pnpm exec wrangler dev` serves it with
Workers routing. Build first in either case. To deploy from your machine,
run `pnpm exec wrangler login`, then `pnpm run deploy` after a successful build.
The Worker name is `slate`.

### Workers Builds

Connect the `slate` Worker to `tylerbutler/slate` with
[Workers Builds](https://developers.cloudflare.com/workers/ci-cd/builds/).
Use these dashboard settings:

| Setting | Value |
|---------|-------|
| Production branch | `main` |
| Root directory | `website` |
| Build command | `pnpm build` |
| Deploy command | `pnpm run deploy` |
| Preview command | `pnpm exec wrangler preview` |
| Build watch include paths | `website/*` |
| Build variable `NODE_VERSION` | `24` |
| Build variable `PNPM_VERSION` | `11.9.0` |

Enable preview builds for non-production branches. Previews do not
replace the production deployment. Cloudflare manages the build API token;
GitHub Actions does not deploy the website.

Keep the empty `previews` block in `website/wrangler.jsonc`.
Wrangler requires it for preview deployments and uses the top-level assets
and compatibility settings. Use `pnpm exec wrangler preview` so Cloudflare
runs the Wrangler version from the project lockfile.

Do not add `.tool-versions` at the repository root. Cloudflare detects it even
for a website build and can fail before it runs the build command. The
[reported failure](https://www.codejam.info/2026/02/cloudflare-workers-choke-asdf-tool-versions.html)
also occurs with `SKIP_DEPENDENCY_INSTALL`. Keep tool versions in `.mise.toml`.

After verifying the Workers deployment, add `slate.tylerbutler.com` as a
custom domain under the Worker's Domains & Routes settings. Remove the
existing Netlify DNS record during that cutover, then disable Netlify's Git
builds. Keep Netlify serving the site until the Workers deployment is ready.
Repository changes do not connect the Cloudflare project or change live DNS.

## Code style

- Format with `just format` — CI enforces formatting.
- Return `Result` from fallible operations. Pure classifiers can return plain
  values. Preserve callback exceptions where the API contract requires them.
- Prefer exhaustive pattern matching over catch-all `_` patterns.
- Document public functions with `///` doc comments.

## Testing conventions

Tests use [Unitest](https://hexdocs.pm/unitest/) with Gleam's built-in assertions.

- Name test functions `{module}_{operation}_test` (e.g., `set_insert_lookup_test`).
- Each test creates a temporary `.dets` file with a unique name.
- Call `cleanup(path)` from `test/test_helper.gleam` at the end of each test to delete the file.
- Use `let assert Ok(...)` for expected-success paths.
- Use `assert actual == expected` for specific value checks.

Run a test file with `gleam test -- test/exclusive_table_test.gleam` or a single
test with `gleam test -- --test exclusive_table_test.set_exclusive_table_test`.
Use `gleam test -- --seed 123` to repeat the same random order.
Do not edit test imports to select tests. Keep the default sequential execution:
tests change VM-wide state, including PATH and debugger breakpoints. Do not use
`--workers` for this suite.
Exclusive tests launch independent BEAM VMs and use a bounded message
protocol. Delete their sidecars only after all child VMs stop.
Resolve nested `erl` and `escript` launchers from the current runtime's
`code:root_dir()/bin`, not inherited PATH: on Windows the root launcher prepends
`erts/bin`, whose `erl.ini` can still contain upstream build paths. Package
children also need root `bin` first on PATH for indirect launches by Gleam.
The VM regression and package proof use broken launchers ahead of the runtime
on PATH to guard this behavior.
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

The release workflow serializes preparation, publication, and recovery in one
non-cancelling queue. On a push to `main`, it checks the previous release's
completion before running `trellis release pr --base main --branch release/next`.
Preparation, publication, and tagging call Trellis directly. The GitHub helper
only selects trusted release revisions and tracks publication/recovery state.
Trellis updates the release PR with the version in `gleam.toml`, new sections
in `.changes/slate/`, and the generated `CHANGELOG.md`. It removes the
fragments it has consumed. Trellis 1.3 stores pending release intent in
`.changes/release.toml`. Refreshes resume that intent and skip unchanged content.
It also updates the locked Slate version in
`examples/dotes/manifest.toml` without downloading or updating Hex dependencies.
The example's release exclusion keeps its version unchanged and prevents
example tags or Hex publication.

Merge that PR to qualify its exact merge revision through the reusable CI
workflow. Publication then assembles the qualified native files, publishes Slate
to Hex, and creates the `v<version>` tag and GitHub Release from the matching
changelog section. A tag push does not start another publication. The workflow
validates the current same-repository merged PR, its ancestry on main, and any
existing tag before publication. It rejects recovery of a superseded release.

The workflows use `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` to prepare PRs,
`HEXPM_API_KEY` for Hex, and the workflow token for tags, GitHub Releases, and
commit statuses. The App needs contents and pull-request write access; the
workflow needs contents, pull-request, and status write access, plus actions
and attestations read access for original SBOM recovery. These existing
credentials and access remain prerequisites. No new approval environment is
required.

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

### Software bills of materials

`just build` and `just build-strict` remove both local SBOM documents before
compilation, then generate two CycloneDX 1.6 JSON documents after the build
succeeds. `just sbom` removes both documents before generation without a build.
Failed compilation or generation cannot leave an inventory from an earlier run.
This cleanup applies only to local generation; recovery keeps the original
qualified SBOM downloads.
`just sbom-check` checks their inventories and dependency graphs against the
current lockfiles. CI generates or restores them before it exports and proves
the five-target Hex package, then uploads the `slate-sbom` artifact.
`just clean` also removes generated local documents.

The assembly/SBOM job uses Ubuntu 24.04 because licence_audit's bundled
Linux runtime requires glibc 2.36 or later. Native Linux builds and their package
proofs still use Ubuntu 22.04 (glibc 2.35).

| File | Tool | Coverage |
|------|------|----------|
| `priv/sbom/slate-gleam.cdx.json` | licence_audit 1.0.0-rc.2 | Root Slate's locked Gleam dependencies, with Hex archive hashes and required/optional runtime/development scopes |
| `priv/sbom/slate-native.cdx.json` | Syft 1.57.0 | The native crate's complete Cargo.lock inventory, including target-specific crates, plus the lockfile hash |

Hex packages include both documents alongside the native libraries. CI compares
the exported package bytes with the qualified documents on Linux and Windows.
Run `gleam export hex-tarball` followed by
`just sbom-package-check build/slate-<version>.tar` to check a local export.
GitHub Release assets keep the filenames `slate-gleam.cdx.json` and
`slate-native.cdx.json`.

Both tools are pinned development tools in `.mise.toml`; neither adds a runtime
or Hex dependency. Slate uses licence_audit's native
distribution includes OTP and supports Slate's OTP 27 host; the escript requires
OTP 28. The reproducible Gleam command needs checksum-verified package metadata
and fails if that metadata is unavailable. It does not scan the dotes example's
local path dependency. Syft scans only `priv/slate_lock/source`, not a container
or a vulnerability service. Its inventory does not assert downloaded Rust crate
hashes; the Cargo.lock hash binds the locked checksums. Its timestamp and serial
metadata can change between generations.

Release qualification creates detached signed GitHub attestations for both
documents; the JSON files contain no embedded signatures. Its final step records
the original artifact ID and ZIP SHA-256 in the `trellis/sbom-qualification` status on the
approved merge revision before qualification can succeed or Hex can publish.
This keeps a cancellation before publication from losing the original identity.
Recovery downloads that exact archive, checks its digest and signed checkout revision,
and checks both inventories against the original checkout. A same-run working
copy does not replace the canonical artifact identity. A missing or expired
archive, conflicting marker, changed bytes, or unavailable attestation blocks
recovery. Keep the original artifact within GitHub's configured retention period;
do not substitute regenerated Syft output or appoint a replacement qualification.

The publisher restores the original documents into `priv/sbom` before package
export and publication. It compares SBOM bytes from any already-published Hex
package before proceeding, including recovery when Trellis skips publication.
After publication it downloads the Hex archive and compares both documents
again before tagging. Missing or different packaged bytes block completion.

After Hex and native tag/release creation, the coordinator verifies the exact
remote tag even when Trellis has no pending tag work. It compares both existing
SBOM assets with the original bytes before any upload, uploads only missing
assets without clobbering, then downloads and compares both final assets before
recording completion. A partial upload can
leave a visible GitHub Release with incomplete assets; recover the same approved
revision. Byte mismatches require investigation, not asset replacement.

This interim flow requires GitHub to permit asset additions to a published
release. If release immutability prevents additions, release remains incomplete;
Trellis needs draft/upload/finalization support before that policy can work.
Do not change repository settings as a workaround. Native asset coordination is
tracked in [tylerbutler/trellis#163](https://github.com/tylerbutler/trellis/issues/163).

### Build attestations

After all CI jobs pass, trusted main builds and merged-release qualification
generate attestations for the five native binaries, complete Hex archive, and
both SBOM documents.
Unmerged PR builds do not run the signing job. Only the signing job receives
`id-token: write` and `attestations: write`; the release caller grants these
permissions to the reusable workflow. A signing failure blocks release
qualification. Attestations use GitHub OIDC and do not require another secret.

`actions/attest` stores SLSA build provenance in GitHub's attestation service.
The provenance identifies the workflow event revision. A separate signed
`https://github.com/tylerbutler/slate/attestations/source-checkout/v1` predicate
records `repository` and the exact checkout `revision`, including when recovery
builds an older release merge.

Verify a downloaded native binary, CI archive, or SBOM document with:

```sh
gh attestation verify path/to/artifact --repo tylerbutler/slate \
  --signer-workflow tylerbutler/slate/.github/workflows/ci.yml
gh attestation verify path/to/artifact --repo tylerbutler/slate \
  --signer-workflow tylerbutler/slate/.github/workflows/ci.yml \
  --predicate-type https://github.com/tylerbutler/slate/attestations/source-checkout/v1 \
  --format json
```

For recovery, also inspect the source-checkout predicate and compare its revision
with the selected release merge. Do not infer that the workflow event revision is
the recovery checkout. These attestations cover CI build artifacts; they do not
assert byte equality with an independently downloaded Hex release archive.

### Release requests and recovery

Use workflow dispatch on `main`, or these authenticated `gh`-backed recipes:

```sh
just release-pr                    # Resume or prepare; skip unchanged content
just release-pr rc                 # Start a candidate cycle
just release-pr none               # Promote the current candidate to final
just release-pr "" 2.3.0            # Request an exact Slate target
just release-pr "" 2.3.0 true       # Replace incompatible pending intent explicitly
just release-recover 123           # Recover merged release PR #123 at its merge SHA
```

Automatic preparation preserves a pending request and continues the label of a
committed candidate. It does not promote a candidate; request `pre=none` to do
that. Each candidate has incremental notes, and promotion rolls up its archived
fragments. A replacement requires an explicit candidate label or target version
and disables resume, automatic candidate selection, and unchanged suppression.
Do not replace an approved candidate with an unrelated target.

The `trellis/release` status on the merge revision records pending, failed, or
completed publication. Pending or failed releases block new preparation.
Recover with the original PR number, or rerun the original merge workflow.
Recovery reruns qualification at that revision, skips an already published Hex
version, and reconciles tags/releases and the original SBOM assets. It records
completion only after Hex, tagging, and both matching attachments succeed.
Completed recovery requests do not publish or prepare again.
Releases shipped before these statuses existed count as complete only when their
tag resolves to the merge SHA and both their GitHub Release and Hex version exist.
API/authentication failures fail the completion check instead of assuming success.

Trellis 1.3 can fail a refresh if GitHub's PR head has not caught up with a branch
push. Do not bypass its revision checks. Once the API shows the current head,
an explicit replacement with the intended target can refresh the PR again.
`just release-cli-check` covers healthy refreshes and this stale-head rejection
against a local API; it does not prove hosted API timing or credential validity.
Runner loss or cancellation can leave the status pending; use the same recovery
path. Do not create tags manually to trigger publication.

The old `just changelog` merge-only recipe has no Trellis equivalent; use the release
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
