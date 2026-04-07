---
title: Error Handling
description: Understanding and handling errors in slate.
---

All slate functions return `Result` types — they never raise exceptions. Errors are represented by the `DetsError` type defined in the `slate` module.

## Error types

### `NotFound`

Returned when looking up a key that does not exist in a set table.

```gleam
import slate
import slate/set

let assert Ok(table) = set.open("data/users.dets")
let assert Error(slate.NotFound) = set.lookup(table, key: "nonexistent")
```

:::note
Bag and duplicate bag tables return an empty list instead of `NotFound` when a key is missing. Only set tables return this error from `lookup`.
:::

### `KeyAlreadyPresent`

Returned by `insert_new` when the key (set) or exact key-value pair (bag) already exists.

```gleam
import slate
import slate/set

let assert Ok(Nil) = set.insert_new(table, "alice", 42)
let assert Error(slate.KeyAlreadyPresent) = set.insert_new(table, "alice", 99)
```

### `AccessDenied`

Returned when attempting a write operation on a table opened with `ReadOnly` access.

```gleam
import slate
import slate/set
import slate.{AutoRepair, ReadOnly}

let assert Ok(table) = set.open_with_access(path: "data/users.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Error(slate.AccessDenied) = set.insert(table, "key", "value")
```

### `TypeMismatch`

Returned when opening a DETS file as a different table type than it was created with. For example, opening a set file as a bag.

```gleam
import slate
import slate/set
import slate/bag

// Create a set table
let assert Ok(table) = set.open("data/store.dets")
let assert Ok(Nil) = set.insert(table, "key", "value")
let assert Ok(Nil) = set.close(table)

// Try to open the same file as a bag — fails
let assert Error(slate.TypeMismatch) = bag.open("data/store.dets")
```

### `FileNotFound`

Returned when the DETS file cannot be found or accessed. This can occur when the file path is invalid or the file system denies access.

### `AlreadyOpen`

Returned when trying to open a table that is already open with a different configuration.

### `TableDoesNotExist`

Returned when performing an operation on a table handle that is no longer valid — for example, after the table has been closed.

### `FileSizeLimitExceeded`

Returned when an operation would cause the DETS file to exceed the 2 GB size limit. See [Limitations](/advanced/limitations/) for details.

### `ErlangError(String)`

A catch-all for unexpected Erlang-level errors. The string contains a formatted description of the underlying Erlang error. If you encounter this error, it may indicate a bug — please [report it](https://github.com/tylerbutler/slate/issues).

## Handling errors

### Pattern matching

Use Gleam's pattern matching to handle specific errors:

```gleam
import slate
import slate/set

case set.lookup(table, key: "config") {
  Ok(value) -> io.println("Found: " <> value)
  Error(slate.NotFound) -> io.println("Key not found, using default")
  Error(other) -> io.println("Unexpected error")
}
```

### Using `let assert`

For cases where you expect the operation to succeed, use `let assert` to crash on failure. This is common in scripts, tests, and initialization code:

```gleam
let assert Ok(table) = set.open("data/cache.dets")
let assert Ok(Nil) = set.insert(table, "key", "value")
```

## Error summary

| Error | Cause | Affected Functions |
|-------|-------|--------------------|
| `NotFound` | Key missing (set tables only) | `lookup` |
| `KeyAlreadyPresent` | Key or pair exists | `insert_new` (set, bag) |
| `AccessDenied` | Write on read-only table | `insert`, `insert_list`, `insert_new`, `delete_*`, `update_counter` |
| `TypeMismatch` | Wrong table type for file | `open`, `open_with`, `open_with_access` |
| `FileNotFound` | File missing or inaccessible | `open`, `open_with`, `open_with_access` |
| `AlreadyOpen` | Table open with different config | `open`, `open_with`, `open_with_access` |
| `TableDoesNotExist` | Invalid table handle | Most operations |
| `FileSizeLimitExceeded` | File would exceed 2 GB | Write operations |
| `ErlangError(msg)` | Unexpected Erlang error | Any |
