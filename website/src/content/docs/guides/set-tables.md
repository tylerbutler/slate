---
title: Set tables
description: Unique key-value storage with DETS set tables.
---

Set tables store one value per key. An entry is one key-value pair. If you insert a pair with an existing key, it replaces that key's value. Use set tables for caches, configuration, and key lookup.

Set tables are provided by the `slate/set` module and correspond to the `set` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

The examples below manage users' ages in one table. Run the snippets in order
within one function, keeping the handle open until the closing step.
The final options section shows separate ways to reopen the saved file.

## Opening and closing

Create the parent directory before opening the table. Use a new file path if
`data/users.dets` already contains data. `open` uses `AutoRepair` and `ReadWrite`.

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let assert Ok(table) = set.open("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int)
```

Keep `table` for the following operations. For short-lived application tasks,
use [`with_table`](/advanced/with-table/) to attempt cleanup when the callback returns.

## Inserting data

Store Alice's age, then add the other users. The batch insert also replaces
Alice's existing value:

```gleam
// Insert a single key-value pair (overwrites if key exists)
let assert Ok(Nil) = set.insert(table, "alice", 42)

// Batch insert multiple pairs
let assert Ok(Nil) = set.insert_list(table, [
  #("alice", 42),
  #("bob", 37),
  #("charlie", 25),
])
```

### Insert without overwriting

Use `insert_new` to insert only if the key does not exist. It returns `Error(KeyAlreadyPresent)` if the key exists.

```gleam
let assert Ok(Nil) = set.insert_new(table, "carol", 42)
let assert Error(slate.KeyAlreadyPresent) = set.insert_new(table, "carol", 99)
```

:::note
Set and bag tables provide `insert_new`, with different duplicate rules. A set rejects an existing key. A bag rejects an existing key-value pair. Duplicate bag tables do not provide this function.
:::

## Looking up data

Read Alice's age and check whether a user exists before you need their value:

```gleam
// Get the value for a key (returns Error(NotFound) if missing)
let assert Ok(42) = set.lookup(table, key: "alice")
let assert Error(slate.NotFound) = set.lookup(table, key: "unknown")

// Check if a key exists without retrieving the value
let assert Ok(True) = set.member(table, key: "alice")
let assert Ok(False) = set.member(table, key: "unknown")
```

## Deleting data

Remove Alice by key and Bob only if his stored age still matches:

```gleam
// Delete a single key
let assert Ok(Nil) = set.delete_key(table, key: "alice")

// Delete only if both the key and value match
let assert Ok(Nil) = set.delete_object(table, key: "bob", value: 37)
```

## Iterating over entries

Carol and Charlie remain in the table. Fold over their ages or count their entries:

```gleam
// Get all entries in an unspecified order (loads the entire table into memory)
let assert Ok(entries) = set.to_list(table)

// Fold over entries in an unspecified order to compute a result
let assert Ok(total) = set.fold(table, from: 0, with: fn(acc, _key, value) {
  acc + value
})

// Get the number of stored entries
let assert Ok(count) = set.size(table)
```

## Atomic counters

You can also store a page-view counter in this integer-valued table.
Set tables support atomic counter increments for integer values:

```gleam
let assert Ok(Nil) = set.insert(table, "page_views", 0)
let assert Ok(1) = set.update_counter(table, "page_views", 1)
let assert Ok(3) = set.update_counter(table, "page_views", 2)
let assert Ok(1) = set.update_counter(table, "page_views", -2)
```

:::note
`update_counter` is only available on set tables, and requires the value to be an integer.
:::

## Flushing writes

Use `sync` to write pending updates to disk without closing the table. DETS saves after an idle period, not at fixed intervals during continuous use. Call `sync` and handle its result when you need to save before continuing:

```gleam
let assert Ok(Nil) = set.insert(table, "checkpoint", 42)
let assert Ok(Nil) = set.sync(table)
// Pending updates are written to disk; the table remains open
```

## Table info

```gleam
let assert Ok(info) = set.info(table)
// info.file_size - size of the file on disk in bytes
// info.object_count - number of entries
// info.file_path - absolute path of the table file
```

`file_path` is the absolute filename used by the shared DETS table. On Unix,
including macOS, slate resolves symlinks; aliases can report the first opener's
filename. Ordinary Windows opens remain path-only. See
[file aliases and platform limits](/advanced/limitations/#file-aliases).
For the 2.0 record change, see [migration guidance](/advanced/stability/).

## Closing the table

Close the handle after these operations to flush pending writes:

```gleam
let assert Ok(Nil) = set.close(table)
```

To discard all entries, call `set.delete_all(table)` before closing.
Closing alone preserves the data for the next open.

## Opening with options

### Repair policy

Select what happens when a table file needs repair. Make a backup before you repair a file with data you need to keep. Repair does not guarantee recovery of all data.

Choose one of these calls. The repair policy has no effect if the table is already open.

```gleam
import slate.{AutoRepair, ForceRepair, NoRepair}
import gleam/dynamic/decode

// Default: auto-repair if needed
let assert Ok(table) = set.open_with(path: "data/users.dets", repair: AutoRepair,
  key_decoder: decode.string, value_decoder: decode.int)

// Repair even if the file was closed properly
let assert Ok(table) = set.open_with(path: "data/users.dets", repair: ForceRepair,
  key_decoder: decode.string, value_decoder: decode.int)

// Return NeedsRepair if the file requires repair
let assert Ok(table) = set.open_with(path: "data/users.dets", repair: NoRepair,
  key_decoder: decode.string, value_decoder: decode.int)
```

Close the handle from whichever call you choose when you finish:

```gleam
let assert Ok(Nil) = set.close(table)
```

### Access mode

Use `ReadOnly` to prevent writes through the table handle. The file must exist.

```gleam
import slate.{AutoRepair, ReadOnly}
import gleam/dynamic/decode

let assert Ok(table) = set.open_with_access(path: "data/users.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.int)
let assert Ok(42) = set.lookup(table, key: "checkpoint")
// set.insert(table, "checkpoint", 99) would return Error(AccessDenied(context))
let assert Ok(Nil) = set.close(table)
```
