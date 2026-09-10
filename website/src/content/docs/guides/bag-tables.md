---
title: Bag tables
description: Multiple distinct values per key with DETS bag tables.
---

Bag tables store multiple distinct values for the same key. An entry is one key-value pair. If a pair exists, `insert` returns `Ok(Nil)` without adding another copy. Use [duplicate bag tables](/guides/duplicate-bag-tables/) to store repeated copies of the same pair.

Bag tables are provided by the `slate/bag` module and correspond to the `bag` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Opening and closing

Create the parent directory before opening the table. `open` uses `AutoRepair` and `ReadWrite`.

```gleam
import gleam/dynamic/decode
import slate
import slate/bag

let assert Ok(table) = bag.open("data/tags.dets",
  key_decoder: decode.string, value_decoder: decode.string)

// ... use the table ...

let assert Ok(Nil) = bag.close(table)
```

For short-lived operations, use [`with_table`](/advanced/with-table/) to close the table when the callback returns.

## Inserting data

```gleam
// Insert multiple distinct values for one key
let assert Ok(Nil) = bag.insert(table, "color", "red")
let assert Ok(Nil) = bag.insert(table, "color", "blue")

// An existing pair returns Ok(Nil) without adding another copy
let assert Ok(Nil) = bag.insert(table, "color", "red")
// The "color" key still has one "red" entry and one "blue" entry

// Batch insert
let assert Ok(Nil) = bag.insert_list(table, [
  #("fruit", "apple"),
  #("fruit", "banana"),
  #("veggie", "carrot"),
])
```

### Detect an existing pair

Use `insert_new` to return an error if the exact key-value pair exists. Other values for the same key do not prevent insertion.

```gleam
let assert Ok(Nil) = bag.insert_new(table, "color", "green")
let assert Error(slate.KeyAlreadyPresent) =
  bag.insert_new(table, "color", "green")
```

Concurrent calls can both return `Ok(Nil)` for the same pair. The table still stores one copy. To ensure only one caller reports a new insertion, serialize writes through an owner process.

## Looking up data

On success, `lookup` returns `Ok(values)`, where `values` is a list of all values for the key. The order is unspecified; do not assume insertion order.

```gleam
let assert Ok(colors) = bag.lookup(table, key: "color")
// Contains each stored color once, in an unspecified order

// Returns an empty list if the key does not exist
let assert Ok([]) = bag.lookup(table, key: "nonexistent")

// Check if a key exists
let assert Ok(True) = bag.member(table, key: "color")
```

## Deleting data

```gleam
// Delete all values for a key
let assert Ok(Nil) = bag.delete_key(table, key: "color")

// Delete a specific key-value pair, preserving other values for the key
let assert Ok(Nil) = bag.insert(table, "color", "red")
let assert Ok(Nil) = bag.insert(table, "color", "blue")
let assert Ok(Nil) = bag.delete_object(table, key: "color", value: "red")
let assert Ok(["blue"]) = bag.lookup(table, key: "color")

// Clear all entries
let assert Ok(Nil) = bag.delete_all(table)
```

## Iterating over entries

```gleam
// Get all entries in an unspecified order (loads the entire table into memory)
let assert Ok(entries) = bag.to_list(table)

// Fold over entries in an unspecified order
let assert Ok(count) = bag.fold(table, from: 0, with: fn(acc, _key, _value) {
  acc + 1
})

// Count entries, not distinct keys
let assert Ok(n) = bag.size(table)
```

## Flushing writes

Use `sync` to flush pending writes to disk without closing the table:

```gleam
let assert Ok(Nil) = bag.sync(table)
// Pending updates are written to disk; the table remains open
```

## Table info

```gleam
let assert Ok(info) = bag.info(table)
// info.file_size - size of the file on disk in bytes
// info.object_count - number of entries, not distinct keys
// info.file_path - absolute path of the table file
```

`file_path` uses the normalized path from `open`; it does not resolve symlinks.
For the 2.0 record change, see [migration guidance](/advanced/stability/).

## Opening with options

### Repair policy

Make a backup before you repair a file with data you need to keep. Repair does not guarantee recovery of all data. See [Repair policies](/advanced/troubleshooting/#repair-policies) to choose an option.

```gleam
import slate.{AutoRepair, ForceRepair, NoRepair}
import gleam/dynamic/decode

let assert Ok(table) = bag.open_with(path: "data/tags.dets", repair: AutoRepair,
  key_decoder: decode.string, value_decoder: decode.string)
```

### Access mode

Use `ReadOnly` to prevent writes through the table handle. The file must exist.

```gleam
import slate.{AutoRepair, ReadOnly}
import gleam/dynamic/decode

let assert Ok(table) = bag.open_with_access(path: "data/tags.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
```

## When to use bag tables

Use bag tables to associate multiple distinct values with one key:

- Map an item to several tags or categories.
- Build secondary indexes over your data.
- Associate a user with several roles, or a post with several comments.
- Group related values under one key.
