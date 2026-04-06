---
title: Set Tables
description: Unique key-value storage with DETS set tables.
---

Set tables store key-value pairs where each key maps to exactly one value. Inserting with an existing key overwrites the previous value. This is the most common table type, ideal for caches, configuration, and general-purpose persistence.

Set tables are provided by the `slate/set` module and correspond to the `set` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Opening and closing

```gleam
import gleam/dynamic/decode
import slate/set

let assert Ok(table) = set.open("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int)

// ... use the table ...

let assert Ok(Nil) = set.close(table)
```

For short-lived operations, use [`with_table`](/advanced/with-table/) to close the table when the callback returns.

## Inserting data

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

Use `insert_new` to insert only if the key does not already exist. Returns `Error(KeyAlreadyPresent)` if the key is taken.

```gleam
let assert Ok(Nil) = set.insert_new(table, "alice", 42)
let assert Error(slate.KeyAlreadyPresent) = set.insert_new(table, "alice", 99)
```

:::note
`insert_new` is only available on set tables. Bag and duplicate bag tables do not have this function.
:::

## Looking up data

```gleam
// Get the value for a key (returns Error(NotFound) if missing)
let assert Ok(42) = set.lookup(table, key: "alice")
let assert Error(slate.NotFound) = set.lookup(table, key: "unknown")

// Check if a key exists without retrieving the value
let assert Ok(True) = set.member(table, key: "alice")
let assert Ok(False) = set.member(table, key: "unknown")
```

## Deleting data

```gleam
// Delete a single key
let assert Ok(Nil) = set.delete_key(table, key: "alice")

// Delete only if both the key and value match
let assert Ok(Nil) = set.delete_object(table, key: "bob", value: 37)

// Clear all entries
let assert Ok(Nil) = set.delete_all(table)
```

## Iterating over entries

```gleam
// Get all entries as a list (loads entire table into memory)
let assert Ok(entries) = set.to_list(table)

// Fold over entries to compute a result
let assert Ok(total) = set.fold(table, from: 0, with: fn(acc, _key, value) {
  acc + value
})

// Get the number of stored entries
let assert Ok(count) = set.size(table)
```

## Atomic counters

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

Use `sync` to flush pending writes to disk without closing the table. This is useful for long-lived tables where you want to ensure durability at a specific point:

```gleam
let assert Ok(Nil) = set.insert(table, "checkpoint", 42)
let assert Ok(Nil) = set.sync(table)
// Data is guaranteed to be on disk, table stays open
```

## Table info

```gleam
let assert Ok(info) = set.info(table)
// info.file_size — size of the file on disk in bytes
// info.object_count — number of entries
```

## Opening with options

### Repair policy

Control how slate handles improperly closed tables:

```gleam
import slate.{AutoRepair, ForceRepair, NoRepair}
import gleam/dynamic/decode

// Default: auto-repair if needed
let assert Ok(table) = set.open_with(path: "data/users.dets", repair: AutoRepair,
  key_decoder: decode.string, value_decoder: decode.int)

// Force repair even if file appears clean
let assert Ok(table) = set.open_with(path: "data/users.dets", repair: ForceRepair,
  key_decoder: decode.string, value_decoder: decode.int)

// Return an error instead of repairing
let assert Ok(table) = set.open_with(path: "data/users.dets", repair: NoRepair,
  key_decoder: decode.string, value_decoder: decode.int)
```

### Access mode

Open a table as read-only to prevent accidental writes:

```gleam
import slate.{AutoRepair, ReadOnly}
import gleam/dynamic/decode

let assert Ok(table) = set.open_with_access(path: "data/users.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.int)
let assert Ok(42) = set.lookup(table, key: "alice")
// set.insert(table, "alice", 99) would return Error(AccessDenied)
```
