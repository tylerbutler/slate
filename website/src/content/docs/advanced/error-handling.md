---
title: Error Handling
description: Understanding and handling errors in slate.
---

All slate functions return `Result` types — they never raise exceptions. Most errors are represented by the `DetsError` type defined in the `slate` module. The single exception is `slate/set.update_counter`, which returns `Result(_, set.UpdateCounterError)` so it can carry the counter-specific `CounterValueNotInteger` case.

For a stable machine-readable code or a user-facing message, use [`slate.error_code`](/advanced/troubleshooting/#using-error_code-and-error_message) and `slate.error_message`.

## File context and migration (breaking)

`FileNotFound`, `AccessDenied`, `TypeMismatch`, `NeedsRepair`, `NotADetsFile`,
and `FileSizeLimitExceeded` now each carry
`FileErrorContext(path: Option(String), reason: String)`.

Before:

```gleam
let assert Error(slate.AccessDenied) = set.insert(table, "key", "value")
let error = slate.NeedsRepair
```

After:

```gleam
import gleam/option.{None}

let assert Error(slate.AccessDenied(context)) = set.insert(table, "key", "value")
let error = slate.NeedsRepair(
  slate.FileErrorContext(path: None, reason: "application requires repair"),
)
```

Use `(_)` instead of `(context)` when only the category matters. Apply this
change to all six constructors, including errors inside `set.TableError`.
`NotFound`, `KeyAlreadyPresent`, and `DecodeErrors` do not change. No DETS
file-format migration is needed, unless your application stores `DetsError`
values themselves as data.

The path is the filename reported by OTP. Opens normally report an absolute
path; `is_dets_file` can report a relative path. `None` means OTP supplied no
single filename—never substitute an empty string or guess from a table-name atom.
For rename failures, both filenames remain in `reason` and `path` is `None`.
Context is kept in the error value and remains usable after the table closes.

The reason retains diagnostic details such as `"enoent"`, `"{error,eacces}"`,
`"access_mode"`, or `"keypos_mismatch"`. Do not parse this text as a stable
classifier. Paths and reasons can be sensitive; use them only in trusted logs.
All `error_code` and safe `error_message` outputs are unchanged and omit context.

An error does not guarantee that a write was rolled back. Avoid blind retries
of non-idempotent writes, keep backups before repair, and close each successful
open. This change does not alter DETS ownership or cleanup behavior.

## Error variants

### `NotFound`

Returned by `set.lookup` when the key does not exist. Bag and duplicate bag tables return `Ok([])` instead — see [Lookup behavior differences](/advanced/troubleshooting/#lookup-behavior-differences).

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let assert Ok(table) = set.open("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int)
let assert Error(slate.NotFound) = set.lookup(table, key: "nonexistent")
```

### `KeyAlreadyPresent`

Returned by `set.insert_new` when the key exists, and by `bag.insert_new` when the exact key-value pair already exists. Plain `insert` never returns this — it overwrites (set) or silently ignores duplicates (bag).

```gleam
let assert Ok(Nil) = set.insert_new(table, "alice", 42)
let assert Error(slate.KeyAlreadyPresent) = set.insert_new(table, "alice", 99)
```

### `AccessDenied`

Returned when file access is denied, or when a write is attempted on a table
opened with `ReadOnly` access. Inspect the context to distinguish the cause.

```gleam
import gleam/dynamic/decode
import slate.{AutoRepair, ReadOnly}
import slate/set

let assert Ok(table) = set.open_with_access(path: "data/users.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Error(slate.AccessDenied(context)) = set.insert(table, "key", "value")
```

### `TypeMismatch`

Returned when opening a DETS file as a different table type than it was created with — for example, opening a set file as a bag.

```gleam
import gleam/dynamic/decode
import slate
import slate/bag
import slate/set

// Create a set table
let assert Ok(table) = set.open("data/store.dets",
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = set.insert(table, "key", "value")
let assert Ok(Nil) = set.close(table)

// Try to open the same file as a bag — fails
let assert Error(slate.TypeMismatch(context)) = bag.open("data/store.dets",
  key_decoder: decode.string, value_decoder: decode.string)
```

### `FileNotFound`

The file or a parent directory is missing. Returned by `open*` or
`is_dets_file` for OTP's `enoent` reason. Permission failures use `AccessDenied`.

### `NotADetsFile`

The path exists and is readable, but the file is not a valid DETS file. Use [`slate.is_dets_file`](/advanced/limitations/#validating-dets-files) to check before opening if you accept untrusted paths.

### `NeedsRepair`

The file was not closed cleanly and you opened it with `NoRepair`. Reopen with `AutoRepair` or `ForceRepair` to recover. See [Repair policies](/advanced/troubleshooting/#repair-policies).

### `AlreadyOpen`

The table is already open with an incompatible configuration (for example, different access mode).

### `TableDoesNotExist`

The table handle is no longer valid — typically because `close` was already called.

### `FileSizeLimitExceeded`

A write would push the DETS file past its 2 GB hard limit. See [Limitations](/advanced/limitations/#file-size-limit) for context and mitigations.

### `TableNamePoolExhausted`

slate uses a bounded internal pool of DETS table name slots. If too many distinct files are open at once, new opens fail with this error. See [Troubleshooting](/advanced/troubleshooting/#tablenamepoolexhausted) for recovery steps.

### `DecodeErrors(List(decode.DecodeError))`

The data on disk did not match the decoders provided when opening the table. See [DecodeErrors](/advanced/troubleshooting/#decodeerrors) for diagnosis and recovery strategies.

### `UnexpectedError(String)`

A catch-all for unexpected Erlang-level errors. The wrapped string is for diagnostics only and is **not** part of slate's stable API contract. Use `slate.error_code(err)` (which returns `"unexpected_error"`) for programmatic matching, and report a [GitHub issue](https://github.com/tylerbutler/slate/issues) if you encounter one.

## `set.update_counter` errors

`update_counter` returns `Result(Int, set.UpdateCounterError)` rather than `DetsError`. The dedicated type adds one operation-specific case without polluting the shared error type:

```gleam
import slate
import slate/set

case set.update_counter(table, key: "hits", increment: 1) {
  Ok(new_value) -> new_value
  Error(set.CounterValueNotInteger) -> 0
  Error(set.TableError(slate.NotFound)) -> 0
  Error(set.TableError(err)) -> panic as slate.error_message(err)
}
```

## Handling errors

### Pattern matching

Match on the variants you expect in normal flows; fall through to a generic branch for the rest:

```gleam
import gleam/io
import slate
import slate/set

case set.lookup(table, key: "config") {
  Ok(value) -> io.println("Found: " <> value)
  Error(slate.NotFound) -> io.println("Key not found, using default")
  Error(other) ->
    io.println("[" <> slate.error_code(other) <> "] " <> slate.error_message(other))
}
```

### Using `let assert`

For paths where you expect success, `let assert` keeps initialization and test code concise:

```gleam
let assert Ok(table) = set.open("data/cache.dets",
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = set.insert(table, "key", "value")
```

## Error summary

| Error | Cause | Typical functions |
|-------|-------|-------------------|
| `NotFound` | Key missing (set tables only) | `set.lookup`, `set.update_counter` (via `TableError`) |
| `KeyAlreadyPresent` | Key (set) or exact pair (bag) already exists | `insert_new` (set, bag) |
| `AccessDenied(_)` | File access denied or write on read-only table | `open*`, `is_dets_file`, write operations |
| `TypeMismatch(_)` | Wrong table type or key position for file | `open`, `open_with`, `open_with_access` |
| `FileNotFound(_)` | File or parent directory missing | `open*`, `is_dets_file` |
| `NotADetsFile(_)` | Path exists but is not a DETS file | `open*` (`is_dets_file` returns `Ok(False)`) |
| `NeedsRepair(_)` | File not closed cleanly, opened with `NoRepair` | `open_with`, `open_with_access` |
| `AlreadyOpen` | Table open with different config | `open*` |
| `TableDoesNotExist` | Invalid table handle (already closed) | Most operations |
| `FileSizeLimitExceeded(_)` | Write would exceed 2 GB | Write operations |
| `TableNamePoolExhausted` | Too many tables open at once | `open*` |
| `DecodeErrors(_)` | On-disk data did not match decoders | Read operations |
| `UnexpectedError(_)` | Unexpected Erlang-level error | Any |
