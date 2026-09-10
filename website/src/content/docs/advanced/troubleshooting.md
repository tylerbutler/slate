---
title: Troubleshooting
description: Diagnose lookup errors, repair needs, and table limits.
---

Use the error variant to identify the problem before you change a file or
retry an operation.

## DecodeErrors

`DecodeErrors` means stored data does not match the decoders you supplied when
opening the table. It indicates a type or format mismatch, not proof of disk
corruption. Possible causes include:

- You changed a type, but the file still contains entries with the old schema.
- You opened a file that uses different key or value types.
- Another tool wrote entries that do not match your decoders.

### Diagnosing the problem

Match `DecodeErrors` to inspect its `decode.DecodeError` values. Each error
describes the expected and found types. Its `path` is a `List(String)` that
locates the error within the value, not a filename. Join its segments for display:

```gleam
import gleam/io
import gleam/list
import gleam/string
import slate
import slate/set

case set.lookup(table, key: "user:1") {
  Ok(value) -> io.println("Found: " <> value)

  Error(slate.DecodeErrors(errors)) -> {
    list.each(errors, fn(err) {
      io.println(
        "Expected " <> err.expected <> " at value path ["
        <> string.join(err.path, ".") <> "], got: " <> err.found,
      )
    })
  }

  Error(other) -> io.println(slate.error_message(other))
}
```

### Recovery strategies

- If you can discard the old data, close the table and delete its `.dets` file.
  The next read-write `open` creates an empty table.
- To keep the data, open the old table with decoders for its old schema.
  Read entries with `fold`, convert them, and write them to a new table.
- To accept more than one schema, use `decode.one_of`.

Use `fold_results` to process readable entries and handle decode errors for
other entries. It passes each entry's decode result to your callback.
It does not repair or rewrite stored data.

## Repair policies

A VM crash or power failure can leave a DETS file in need of repair.
`RepairPolicy` controls whether DETS attempts repair when you open the file.

### When to use each policy

| Policy | Behavior | Use when |
|--------|----------|----------|
| `AutoRepair` | Attempts repair if needed | Allow DETS to attempt repair during open. This is the default policy. |
| `ForceRepair` | Repairs the file even if it was properly closed | Explicitly request repair after you back up the file. |
| `NoRepair` | Returns `NeedsRepair` if repair is required | Detect a repair requirement without attempting repair. |

No policy guarantees full data recovery. A successful open does not certify
that every stored entry is intact or matches your schema.

### Example: recovering after a crash

:::caution
Before you attempt repair, stop access to the file and make a backup of the
closed file. Repair can change the file and may not recover all data. Run the
example below only after the backup succeeds.
:::

After the backup, use `ForceRepair` to request repair:

```gleam
import gleam/dynamic/decode
import slate.{ForceRepair}
import slate/set

let repair_result =
  set.open_with(path: "data/important.dets", repair: ForceRepair,
    key_decoder: decode.string, value_decoder: decode.int)
```

Handle `repair_result`. If it is `Ok(table)`, check the recovered data and
close the table when you finish. An open error does not confirm that repair
left the file unchanged.

<a id="example-detecting-corruption-explicitly"></a>

### Example: detecting a repair requirement

Use `NoRepair` to detect whether the file needs repair without attempting repair.
This example reports `NeedsRepair` and returns it to the caller. It does not
attempt repair or treat other errors as corruption:

```gleam
import gleam/dynamic/decode
import gleam/io
import slate.{NoRepair, ReadOnly}
import slate/set

case set.open_with_access(path: "data/important.dets",
  repair: NoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.int)
{
  Ok(table) -> Ok(table)
  Error(slate.NeedsRepair(context)) -> {
    io.println("Repair required. Stop file access and back up the file before repair.")
    Error(slate.NeedsRepair(context))
  }
  Error(other) -> Error(other)
}
```

`ReadOnly` requires an existing file. The caller must close a successfully
opened table. If repair is required,
complete the backup step before using the separate repair example above.

## TableNamePoolExhausted

slate has 4096 DETS table name slots. The pool supports up to 4096 concurrently
open distinct normalized paths. When all slots are in use, opening another
path returns `TableNamePoolExhausted`. Closing a table releases its slot for
reuse. Opening a path does not permanently consume a slot.

### Why it happens

- You opened thousands of distinct paths without closing the tables.
- You created a separate file for each user or other entity and kept those tables open.

### How to recover

1. Call `close` on tables you no longer need to release their slots.
2. Store entries for multiple entities in one table with structured keys.
3. Use [`with_table`](/advanced/with-table/) for short-lived operations. It
   attempts to close the table when the callback returns or raises. Handle its
   result; a callback error does not confirm that closing succeeded.

### Checking for this error

```gleam
import gleam/io
import gleam/dynamic/decode
import slate
import slate/set

case set.open("data/table_4097.dets",
  key_decoder: decode.string, value_decoder: decode.string)
{
  Ok(table) -> Ok(table)
  Error(slate.TableNamePoolExhausted) -> {
    io.println("Too many open tables. Close some before opening another path.")
    Error(slate.TableNamePoolExhausted)
  }
  Error(other) -> Error(other)
}
```

The caller must close the table if opening succeeds.

## Lookup behavior differences

The three table types return different result shapes from `lookup`:

| Table type | Return type | Missing key returns |
|------------|-------------|---------------------|
| `set` | `Result(value, DetsError)` | `Error(NotFound)` |
| `bag` | `Result(List(value), DetsError)` | `Ok([])` |
| `duplicate_bag` | `Result(List(value), DetsError)` | `Ok([])` |

### Set lookup

Set tables store one value per key. `lookup` returns `Ok(value)` when the key
exists, or `Error(NotFound)` when it does not. This example uses an application
default of `0` only for a missing key. It returns other errors:

```gleam
import slate
import slate/set

case set.lookup(table, key: "alice") {
  Ok(age) -> Ok(age)
  Error(slate.NotFound) -> Ok(0)
  Error(other) -> Error(other)
}
```

### Bag and duplicate bag lookup

Bag and duplicate bag lookups return a `Result`. A successful result contains
a list of values. `Ok([])` means the key does not exist:

```gleam
import gleam/list
import slate/bag

let assert Ok(tags) = bag.lookup(table, key: "article:1")
case list.is_empty(tags) {
  True -> ["untagged"]
  False -> tags
}
```

`let assert` panics if lookup returns an error. Use pattern matching when you
need to handle that error.

To detect a missing key, match `Error(NotFound)` for a set or `Ok([])` for a
bag or duplicate bag.

## delete_object for duplicate_bag

`delete_key` removes all entries with the specified key. `delete_object`
removes entries whose key and value both match. A duplicate bag can contain
multiple copies of one entry.

### Example

```gleam
import slate/duplicate_bag

// Table contains: ("color", "red"), ("color", "red"), ("color", "blue")

// Remove all copies of the matching entry
let assert Ok(Nil) = duplicate_bag.delete_object(table, key: "color", value: "red")
// Now contains only: ("color", "blue")

// Remove every entry with the key
let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "color")
// Now contains nothing for "color"
```

:::note
`delete_object` removes all copies of the matching entry from a duplicate bag.
If you inserted the same entry three times, one call removes all three copies.
:::

For bag tables, `delete_object` removes the matching entry. A bag cannot
contain duplicate entries.

For set tables, `delete_object` removes the entry only if both its key and
value match. Use `delete_key` to remove an entry by key, regardless of its value.

## Using error_code and error_message

`slate.error_code(error)` returns a stable, machine-readable string such as
`"not_found"` or `"decode_error"`. Use it for logging, metrics, and programmatic
error handling.

`slate.error_message(error)` returns a human-readable description such as
`"No value was found for the requested key."` Use it for display or logging,
not programmatic matching. Message text may change in any release.

Neither helper includes file-error context. Paths and diagnostic reasons can
contain sensitive data. Keep them in trusted logs. See
[File context and migration](/advanced/error-handling/#file-context-and-migration-breaking)
for the seven constructors that contain `FileErrorContext`.

### Error code reference

| Error | Code | Message |
|-------|------|---------|
| `NotFound` | `"not_found"` | No value was found for the requested key. |
| `FileNotFound(_)` | `"file_not_found"` | The DETS file could not be found. |
| `AlreadyOpen(_)` | `"already_open"` | The table is already open with incompatible options. |
| `TableDoesNotExist` | `"table_does_not_exist"` | The table is not currently open. |
| `FileSizeLimitExceeded(_)` | `"file_size_limit_exceeded"` | The DETS file exceeded the 2 GB size limit. |
| `KeyAlreadyPresent` | `"key_already_present"` | The key or key-value pair is already present. |
| `AccessDenied(_)` | `"access_denied"` | The requested operation is not allowed with the current access mode. |
| `TypeMismatch(_)` | `"type_mismatch"` | The file was opened with the wrong DETS table type. |
| `NotADetsFile(_)` | `"not_a_dets_file"` | The file exists but is not a valid DETS file. |
| `NeedsRepair(_)` | `"needs_repair"` | The table file was not closed cleanly and needs repair. Open with AutoRepair or ForceRepair. |
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
      slate.DecodeErrors(_) -> Error("Session data does not match the expected format")
      _ -> Error("Storage error: " <> slate.error_message(err))
    }
  }
}
```
