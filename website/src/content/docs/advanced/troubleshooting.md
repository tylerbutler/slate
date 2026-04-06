---
title: Troubleshooting
description: Common issues and edge cases when working with slate, with guidance on diagnosis and recovery.
---

This page covers common issues you may encounter when working with slate, along with explanations and recovery strategies.

## DecodeErrors

`DecodeErrors` is returned when data stored on disk does not match the Gleam decoders you provided when opening the table. This typically happens when:

- **Schema changes** — you changed the value type (e.g., from `String` to `Int`) but the file still contains data written with the old schema.
- **Wrong file** — you opened a DETS file that was written by a different application or with different key/value types.
- **Manual edits** — the file was modified outside of slate.

### Diagnosing the problem

Pattern match on the `DecodeErrors` variant to inspect the list of `decode.DecodeError` values. Each entry describes what the decoder expected versus what it found on disk:

```gleam
import gleam/dynamic/decode
import gleam/io
import gleam/list
import slate
import slate/set

case set.lookup(table, key: "user:1") {
  Ok(value) -> io.println("Found: " <> value)

  Error(slate.DecodeErrors(errors)) -> {
    list.each(errors, fn(err) {
      io.println(
        "Expected " <> err.expected <> " at " <> err.path
        <> ", got: " <> err.found,
      )
    })
  }

  Error(other) -> io.println(slate.error_message(other))
}
```

### Recovery strategies

- **Re-create the table**: Delete the `.dets` file and let slate create a fresh one on the next `open` call. This is the simplest option when the old data is expendable.
- **Migrate data**: Open the old table using decoders that match the *old* schema, read all entries with `fold`, then write them into a new table with the updated schema.
- **Use flexible decoders**: If your schema evolves over time, design your decoders to accept multiple shapes using `decode.one_of`.

## Repair policies

When a DETS file is not closed properly — for example, after a crash or power failure — it may be in an inconsistent state. The `RepairPolicy` controls what happens when slate opens such a file.

### When to use each policy

| Policy | Behavior | Use when |
|--------|----------|----------|
| `AutoRepair` | Silently repairs corruption on open | Default for most applications. Good for caches and data that should "just work." |
| `ForceRepair` | Rebuilds the file even if no corruption is detected | Recovering from suspected silent corruption, or after a crash where you want to be certain the file is consistent. |
| `NoRepair` | Returns an error if corruption is found | Production systems where you want to detect corruption explicitly and handle it on your own terms. |

### Example: recovering after a crash

If your application crashed and you suspect the DETS file may be corrupted, open it with `ForceRepair` to rebuild:

```gleam
import gleam/dynamic/decode
import slate.{ForceRepair}
import slate/set

let assert Ok(table) =
  set.open_with("data/cache.dets", ForceRepair,
    key_decoder: decode.string, value_decoder: decode.string)
```

### Example: detecting corruption explicitly

Use `NoRepair` when you want to know about corruption rather than silently fixing it:

```gleam
import gleam/dynamic/decode
import gleam/io
import slate.{ForceRepair, NoRepair}
import slate/set

case set.open_with("data/important.dets", NoRepair,
  key_decoder: decode.string, value_decoder: decode.int)
{
  Ok(table) -> {
    // File is clean, proceed normally
    table
  }
  Error(_) -> {
    io.println("Corruption detected — forcing repair")
    let assert Ok(table) =
      set.open_with("data/important.dets", ForceRepair,
        key_decoder: decode.string, value_decoder: decode.int)
    table
  }
}
```

## TableNamePoolExhausted

Slate uses a fixed internal pool of 4096 DETS table name slots. Each unique file path that you open consumes one slot. When all slots are in use, `open` returns `TableNamePoolExhausted`.

### Why it happens

- Opening thousands of distinct file paths without closing them.
- Dynamically generating file paths (e.g., one file per user) in a long-running application.

### How to recover

1. **Close unused tables** — call `close` on tables you no longer need. This frees their pool slots for reuse.
2. **Reuse file paths** — instead of creating a new file per entity, store multiple entities in one table using structured keys.
3. **Use `with_table`** — the [`with_table`](/advanced/with-table/) helper automatically closes the table when the callback returns, preventing slot leaks.

### Checking for this error

```gleam
import gleam/io
import gleam/dynamic/decode
import slate
import slate/set

case set.open("data/table_4097.dets",
  key_decoder: decode.string, value_decoder: decode.string)
{
  Ok(table) -> table
  Error(slate.TableNamePoolExhausted) -> {
    io.println("Too many open tables — close some before opening new ones")
    panic as "table name pool exhausted"
  }
  Error(other) -> panic as slate.error_message(other)
}
```

## Lookup behavior differences

The three table types return different result shapes from `lookup`:

| Table type | Return type | Missing key returns |
|------------|-------------|---------------------|
| `set` | `Result(value, DetsError)` | `Error(NotFound)` |
| `bag` | `Result(List(value), DetsError)` | `Ok([])` |
| `duplicate_bag` | `Result(List(value), DetsError)` | `Ok([])` |

### Set lookup

Set tables store one value per key. `lookup` returns the value directly, or `NotFound` if the key does not exist:

```gleam
import slate
import slate/set

case set.lookup(table, key: "alice") {
  Ok(age) -> age
  Error(slate.NotFound) -> 0
  Error(other) -> panic as slate.error_message(other)
}
```

### Bag and duplicate bag lookup

Bag tables store multiple values per key. `lookup` always returns a list — an empty list means the key was not found:

```gleam
import gleam/list
import slate/bag

let assert Ok(tags) = bag.lookup(table, key: "article:1")
case list.is_empty(tags) {
  True -> ["untagged"]
  False -> tags
}
```

This difference matters when you branch on "key exists vs. key missing." With set tables, check for `Error(NotFound)`. With bag and duplicate bag tables, check for an empty list.

## delete_object for duplicate_bag

The `delete` function removes *all* values associated with a key. In contrast, `delete_object` removes only the exact key-value pair you specify. This distinction is most useful with duplicate bag tables, where a single key can have multiple values — including duplicates.

### Example

```gleam
import slate/duplicate_bag

// Table contains: ("color", "red"), ("color", "red"), ("color", "blue")

// delete_object removes all exact matches of the key-value pair
let assert Ok(Nil) = duplicate_bag.delete_object(table, key: "color", value: "red")
// Now contains only: ("color", "blue")
// Both copies of ("color", "red") were removed

// To remove all values for a key regardless of value, use delete instead
let assert Ok(Nil) = duplicate_bag.delete(table, key: "color")
// Now contains nothing for "color"
```

:::note
`delete_object` removes **all** copies of the matching key-value pair from a duplicate bag. If you inserted the same pair three times, one `delete_object` call removes all three copies.
:::

For **bag** tables, `delete_object` works the same way — it removes the specific key-value pair. Since bag tables do not store duplicate pairs, one call is always sufficient.

For **set** tables, `delete_object` removes the entry only if both the key *and* value match what is stored. If you only want to delete by key regardless of value, use `delete` instead.

## Using error_code and error_message

Slate provides two helper functions for working with errors programmatically:

- **`slate.error_code(error)`** returns a stable, machine-readable string like `"not_found"` or `"decode_error"`. Use this for logging, metrics, and programmatic error handling.
- **`slate.error_message(error)`** returns a human-readable description like `"No value was found for the requested key."` Use this for user-facing messages and debug output.

### Error code reference

| Error | Code | Message |
|-------|------|---------|
| `NotFound` | `"not_found"` | No value was found for the requested key. |
| `FileNotFound` | `"file_not_found"` | The DETS file could not be found. |
| `AlreadyOpen` | `"already_open"` | The table is already open with incompatible options. |
| `TableDoesNotExist` | `"table_does_not_exist"` | The table is not currently open. |
| `FileSizeLimitExceeded` | `"file_size_limit_exceeded"` | The DETS file exceeded the 2 GB size limit. |
| `KeyAlreadyPresent` | `"key_already_present"` | The key or key-value pair is already present. |
| `AccessDenied` | `"access_denied"` | The requested operation is not allowed with the current access mode. |
| `TypeMismatch` | `"type_mismatch"` | The file was opened with the wrong DETS table type. |
| `TableNamePoolExhausted` | `"table_name_pool_exhausted"` | Too many different DETS tables are open at once. |
| `DecodeErrors(_)` | `"decode_error"` | Data on disk did not match the expected Gleam types. |
| `UnexpectedError(_)` | `"unexpected_error"` | An unexpected DETS error occurred. |

### Example: structured error handling

```gleam
import gleam/io
import slate
import slate/set

case set.lookup(table, key: "session:abc") {
  Ok(value) -> Ok(value)
  Error(err) -> {
    // Log the stable code for monitoring and alerting
    io.println("[slate:" <> slate.error_code(err) <> "] " <> slate.error_message(err))

    // Branch on specific errors using pattern matching
    case err {
      slate.NotFound -> Error("Session not found")
      slate.DecodeErrors(_) -> Error("Corrupt session data")
      _ -> Error("Storage error: " <> slate.error_message(err))
    }
  }
}
```
