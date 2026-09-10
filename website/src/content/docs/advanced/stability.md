---
title: Stability and versioning
---

slate follows [Semantic Versioning](https://semver.org/). The guarantees below
apply to the public API.

## Public API surface

The following modules make up the supported public API:

| Module | Purpose |
|--------|---------|
| `slate` | Shared types (`DetsError`, `FileErrorContext`, `AccessMode`, `RepairPolicy`, `TableInfo`) and helper functions (`error_code`, `error_message`, `is_dets_file`) |
| `slate/set` | Set tables with one value per key |
| `slate/bag` | Bag tables with multiple distinct values per key |
| `slate/duplicate_bag` | Duplicate bag tables that allow duplicate entries |

Semantic Versioning covers all public functions and types in these modules.

## Internal surfaces

The Erlang FFI files (`slate_dets_ffi.erl` and `slate_with_table_ffi.erl`) are
internal implementation details. They are not part of the public API and may
change in any release without notice. Use the Gleam modules instead of calling
FFI functions directly.

## Semver policy

| Release type | What changes |
|-------------|-------------|
| Patch (for example, 2.0.0 to 2.0.1) | Bug fixes only. No new features or breaking changes. |
| Minor (for example, 2.0.0 to 2.1.0) | Compatible additions, such as new functions. Existing code continues to compile and work. |
| Major (for example, 1.0.0 to 2.0.0) | Breaking changes, such as renamed functions, changed return types, added or removed type variants, or new record fields. |

## Stable error codes

The strings returned by `slate.error_code` are stable across minor and patch
releases. Use them for programmatic matching, logging, or metrics.

```gleam
case slate.error_code(error) {
  "not_found" -> handle_missing()
  "access_denied" -> handle_permission_error()
  code -> log_unexpected(code)
}
```

`slate.error_message` returns human-readable descriptions for display or logging.
These strings may change in any release. Do not use them for programmatic matching.

## Diagnostics-only surfaces

`UnexpectedError(detail)` contains an unexpected Erlang error as a formatted
string. `FileErrorContext.reason` contains a diagnostic reason from OTP.
Neither string is a stable API. Both may change in any release.

Use error variants or `error_code` for programmatic matching. `error_message`
returns a generic message for `UnexpectedError` and omits file-error context.
Paths and diagnostic reasons may contain sensitive data. Keep them in trusted logs.

## Upgrade guidance

- [CHANGELOG.md](https://github.com/tylerbutler/slate/blob/main/CHANGELOG.md) contains release notes.
- [GitHub Releases](https://github.com/tylerbutler/slate/releases) contains tagged releases and downloads.

Before a major upgrade, read the changelog for migration notes and breaking
changes. Minor and patch upgrades preserve compatibility.

For 2.0, also update [file-error constructors](/advanced/error-handling/#file-context-and-migration-breaking)
and [`with_table` calls](/advanced/with-table/#migrating-from-1x).

### TableInfo in 2.0

In 2.0, `TableInfo` includes `file_path: String`. The `info()` functions in all
three table modules return the normalized absolute path, file size, and entry count.
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
longer open. Other stored entries need no migration for this change. If your
application stores `TableInfo` records as data, migrate those records to the
new shape.
