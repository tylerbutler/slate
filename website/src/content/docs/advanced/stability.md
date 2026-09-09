---
title: Stability & Versioning
---

slate 1.0 is released: the public API is stable and covered by [Semantic Versioning](https://semver.org/). This page describes which parts of the library are covered by versioning guarantees and what to expect across releases.

## Public API surface

The following modules make up the supported public API:

| Module | Purpose |
|--------|---------|
| `slate` | Shared types (`DetsError`, `AccessMode`, `RepairPolicy`, `TableInfo`) and helper functions (`error_code`, `error_message`, `is_dets_file`) |
| `slate/set` | Set tables — one value per key |
| `slate/bag` | Bag tables — multiple distinct values per key |
| `slate/duplicate_bag` | Duplicate bag tables — duplicate key-value pairs allowed |

All public functions in these modules are covered by semver guarantees.

## Internal surfaces

The Erlang FFI files (`slate_dets_ffi.erl` and `slate_with_table_ffi.erl`) are internal implementation details. They are **not** part of the public API and may change in any release without notice. Do not call FFI functions directly — use the Gleam module APIs instead.

## Semver policy

| Release type | What changes |
|-------------|-------------|
| **Patch** (e.g., 1.0.0 → 1.0.1) | Bug fixes only. No new features, no breaking changes. |
| **Minor** (e.g., 1.0.0 → 1.1.0) | Backward-compatible additions — new functions, new options. Existing code continues to compile and work. |
| **Major** (e.g., 1.0.0 → 2.0.0) | Breaking changes — removed or renamed functions, changed return types, added or removed type variants, new record fields. |

## Stable error codes

The strings returned by `slate.error_code` are stable across minor and patch releases. You can safely use them for programmatic matching — for example, in error-handling logic, logging, or metrics.

```gleam
case slate.error_code(error) {
  "not_found" -> handle_missing()
  "access_denied" -> handle_permission_error()
  code -> log_unexpected(code)
}
```

The strings returned by `slate.error_message` are human-readable descriptions intended for display or logging. They may change in any release and should not be used for programmatic matching.

## Diagnostics-only surfaces

The `UnexpectedError(detail)` variant of `DetsError` wraps unexpected Erlang error terms as a formatted string. The detail string is **not** a stable API contract — it may change across any release. `error_message` intentionally returns a generic message for this variant. Use `error_code` instead for reliable programmatic matching.

## Upgrade guidance

- **[CHANGELOG.md](https://github.com/tylerbutler/slate/blob/main/CHANGELOG.md)** — release history with detailed notes for every version.
- **[GitHub Releases](https://github.com/tylerbutler/slate/releases)** — tagged releases with download links.

When upgrading across major versions, check the changelog for migration notes and breaking changes. Minor and patch upgrades should be drop-in replacements.

### TableInfo in 2.0

`TableInfo` now includes `file_path: String`. The `info()` functions in all three
table modules return the normalized absolute path, file size, and object count.
Existing field access remains valid. Update constructor calls and full
constructor patterns:

Before:

```gleam
let slate.TableInfo(file_size, object_count) = info
let copy = slate.TableInfo(file_size:, object_count:)
```

After:

```gleam
let slate.TableInfo(file_size, object_count, file_path) = info
let copy = slate.TableInfo(file_size:, object_count:, file_path:)
```

If you only need selected fields, use a partial pattern such as
`let slate.TableInfo(object_count:, ..) = info`.

`info()` remains fallible and returns `TableDoesNotExist` when the table is no
longer open. Ordinary DETS records need no migration. If your application stores
`TableInfo` records as data, migrate those records to the new shape.
