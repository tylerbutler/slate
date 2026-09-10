---
title: Error handling
description: Handle table errors and inspect diagnostic context.
---

Table operations return `Result` values. Most use `slate.DetsError` for errors.
`slate/set.update_counter` uses `set.UpdateCounterError` instead.
The helpers `slate.error_code` and `slate.error_message` return `String` values.

Callbacks passed to `with_table`, `fold`, or `fold_results` can raise exceptions.
Those exceptions propagate to the caller. `with_table` attempts to close the
table before it re-raises a callback exception.

For a stable machine-readable code or a user-facing message, use [`slate.error_code`](/advanced/troubleshooting/#using-error_code-and-error_message) and `slate.error_message`.

## Handling errors

### Pattern matching

Match the errors that your application expects. Handle or return other errors:

```gleam
import gleam/io
import slate
import slate/set

case set.lookup(table, key: "config") {
  Ok(value) -> io.println("Found: " <> value)
  Error(slate.NotFound) -> io.println("Configuration key not found")
  Error(other) ->
    io.println("[" <> slate.error_code(other) <> "] " <> slate.error_message(other))
}
```

### Using `let assert`

`let assert` panics if the result does not match the pattern. Use it in tests
or when a failure should stop the current process. Use pattern matching or
`result.try` when the caller must handle the error.

```gleam
let assert Ok(table) = set.open("data/cache.dets",
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = set.insert(table, "key", "value")
let assert Ok(Nil) = set.close(table)
```

## Error variants

### `NotFound`

`set.lookup` returns this error when the key does not exist. Bag and duplicate bag tables return `Ok([])` instead. See [Lookup behavior differences](/advanced/troubleshooting/#lookup-behavior-differences).

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let assert Ok(table) = set.open("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int)
let assert Error(slate.NotFound) = set.lookup(table, key: "nonexistent")
let assert Ok(Nil) = set.close(table)
```

### `KeyAlreadyPresent`

`set.insert_new` returns this error when the key exists. `bag.insert_new` returns it when the exact entry already exists. Plain `insert` does not return this error. It replaces the value in a set or ignores a duplicate entry in a bag.

```gleam
let assert Ok(Nil) = set.insert_new(table, "alice", 42)
let assert Error(slate.KeyAlreadyPresent) = set.insert_new(table, "alice", 99)
```

### `AccessDenied`

This error indicates denied file access or an attempted write to a table
opened with `ReadOnly` access. Inspect the context to identify the cause.

```gleam
import gleam/dynamic/decode
import slate.{AutoRepair, ReadOnly}
import slate/set

let assert Ok(table) = set.open_with_access(path: "data/users.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Error(slate.AccessDenied(context)) = set.insert(table, "key", "value")
let assert Ok(Nil) = set.close(table)
```

### `TypeMismatch`

Opening a DETS file with the wrong table type or key position returns this
error. For example, you cannot open a set file as a bag.

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

// Opening the same file as a bag fails
let assert Error(slate.TypeMismatch(context)) = bag.open("data/store.dets",
  key_decoder: decode.string, value_decoder: decode.string)
```

### `FileNotFound`

The file or a parent directory is missing. Returned by `open*` or
`is_dets_file` for OTP's `enoent` reason. Permission failures use `AccessDenied`.

### `NotADetsFile`

The path exists and is readable, but the file is not a valid DETS file.
[`slate.is_dets_file`](/advanced/limitations/#validating-dets-files) can identify
DETS files before you open them. It does not guarantee integrity or safe access
to untrusted paths.

### `NeedsRepair`

The file needs repair, and you opened it with `NoRepair`. Back up the closed
file before you attempt repair with `AutoRepair` or `ForceRepair`. Repair
does not guarantee full data recovery. See [Repair policies](/advanced/troubleshooting/#repair-policies).

### `AlreadyOpen`

The table is already open with an incompatible configuration (for example, different access mode).
Match `AlreadyOpen(context)` to inspect the path and the
`"incompatible_arguments"` reason.

### `TableDoesNotExist`

The table handle is no longer valid, usually because the table is already closed.

### `FileSizeLimitExceeded`

A write would push the DETS file past its 2 GB hard limit. See [Limitations](/advanced/limitations/#file-size-limit) for context and mitigations.

### `TableNamePoolExhausted`

slate uses a bounded internal pool of DETS table name slots. If too many distinct files are open at once, new opens fail with this error. See [Troubleshooting](/advanced/troubleshooting/#tablenamepoolexhausted) for recovery steps.

### `DecodeErrors(List(decode.DecodeError))`

The data on disk did not match the decoders provided when opening the table. See [DecodeErrors](/advanced/troubleshooting/#decodeerrors) for diagnosis and recovery strategies.

### `UnexpectedError(String)`

This variant contains an unexpected Erlang-level error. The string is for
diagnostics only and is not a stable API. Use `slate.error_code(err)`, which
returns `"unexpected_error"`, for programmatic matching. Report a
[GitHub issue](https://github.com/tylerbutler/slate/issues) if you encounter one.

## `set.update_counter` errors

`update_counter` returns `Result(Int, set.UpdateCounterError)`. This type adds
`CounterValueNotInteger` without adding a counter-specific variant to `DetsError`:

```gleam
import gleam/int
import gleam/io
import slate
import slate/set

case set.update_counter(table, key: "hits", increment: 1) {
  Ok(new_value) -> io.println("Hits: " <> int.to_string(new_value))
  Error(set.CounterValueNotInteger) -> io.println("The counter value is not an integer")
  Error(set.TableError(slate.NotFound)) -> io.println("The counter key does not exist")
  Error(set.TableError(err)) -> io.println(slate.error_message(err))
}
```

## File context and migration (breaking)

### Current file context

`FileNotFound`, `AlreadyOpen`, `AccessDenied`, `TypeMismatch`, `NeedsRepair`,
`NotADetsFile`, and `FileSizeLimitExceeded` each contain
`FileErrorContext(path: Option(String), reason: String)`.

The path is the filename that OTP reports. If OTP returns `AlreadyOpen` without
a path, open operations retain the path they passed to OTP. Open operations
normally report an absolute path. `is_dets_file` can report a relative path.

`None` means there is no single filename. Do not substitute an empty string or
guess from a table-name atom. For rename failures, `reason` retains both
filenames and `path` is `None`. The context remains available after the table
closes.

The reason retains diagnostic details such as `"enoent"`, `"{error,eacces}"`,
`"access_mode"`, or `"keypos_mismatch"`. Do not parse this text to identify the
error category.
Paths and reasons can contain sensitive data. Use them only in trusted logs.
`error_code` and `error_message` omit this context.

An error does not guarantee that a write was rolled back. Do not retry a
non-idempotent write without checking its effect. Back up files before repair,
and close each successful open.

### Migrating from 1.x

In 2.0, all seven file-error constructors require context.

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

Use `(_)` instead of `(context)` when you only need the category. Update all
seven constructors, including errors inside `set.TableError`. `NotFound`,
`KeyAlreadyPresent`, and `DecodeErrors` are unchanged.

No DETS file-format migration is needed unless your application stores
`DetsError` values as data. The `error_code` and `error_message` outputs are
unchanged. This change does not alter DETS ownership or cleanup behavior.

## Error summary

| Error | Cause | Typical functions |
|-------|-------|-------------------|
| `NotFound` | Key missing (set tables only) | `set.lookup`, `set.update_counter` (via `TableError`) |
| `KeyAlreadyPresent` | Key (set) or exact entry (bag) already exists | `insert_new` (set, bag) |
| `AccessDenied(_)` | File access denied or write on read-only table | `open*`, `is_dets_file`, write operations |
| `TypeMismatch(_)` | Wrong table type or key position for file | `open`, `open_with`, `open_with_access` |
| `FileNotFound(_)` | File or parent directory missing | `open*`, `is_dets_file` |
| `NotADetsFile(_)` | Path exists but is not a DETS file | `open*` (`is_dets_file` returns `Ok(False)`) |
| `NeedsRepair(_)` | File not closed cleanly, opened with `NoRepair` | `open_with`, `open_with_access` |
| `AlreadyOpen(context)` | Table open with incompatible options | `open*` |
| `TableDoesNotExist` | Invalid table handle (already closed) | Most operations |
| `FileSizeLimitExceeded(_)` | Write would exceed 2 GB | Write operations |
| `TableNamePoolExhausted` | Too many tables open at once | `open*` |
| `DecodeErrors(_)` | On-disk data did not match decoders | Read operations |
| `UnexpectedError(_)` | Unexpected Erlang-level error | Any |
