---
title: Bag tables
description: Multiple distinct values per key with DETS bag tables.
---

Bag tables store multiple distinct values for the same key. An entry is one key-value pair. If a pair exists, `insert` returns `Ok(Nil)` without adding another copy. Use [duplicate bag tables](/guides/duplicate-bag-tables/) to store repeated copies of the same pair.

Bag tables are provided by the `slate/bag` module and correspond to the `bag` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

<a id="when-to-use-bag-tables"></a>

Use a bag to associate an item with tags or categories, build secondary indexes,
or group values such as user roles or post comments under one key.
The examples below group colors and foods. Run the snippets in order within
one function, keeping the handle open until the closing step.
The final options section shows separate ways to reopen the saved file.

## Opening and closing

Create the parent directory before opening the table. Use a new file path if
`data/tags.dets` already contains data. `open` uses `AutoRepair` and `ReadWrite`.

```gleam
import gleam/dynamic/decode
import slate
import slate/bag

let assert Ok(table) = bag.open("data/tags.dets",
  key_decoder: decode.string, value_decoder: decode.string)
```

Keep `table` for the following operations. For short-lived application tasks,
use [`with_table`](/advanced/with-table/) to attempt cleanup when the callback returns.

## Inserting data

Add colors under one key. Inserting red twice keeps one copy, so repeated
tag assignments do not create duplicate entries:

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

A plain `insert` does not tell you whether the pair was new. When you need to
know, use `insert_new`. It returns an error if the exact key-value pair exists.
Other values for the same key do not prevent insertion:

```gleam
let assert Ok(Nil) = bag.insert_new(table, "color", "green")
let assert Error(slate.KeyAlreadyPresent) =
  bag.insert_new(table, "color", "green")
```

Concurrent calls can both return `Ok(Nil)` for the same pair. The table still stores one copy. To ensure only one caller reports a new insertion, serialize writes through an owner process.

## Looking up data

Read the colors you assigned. The earlier `insert_new` added green to red and
blue, so the lookup returns three values. On success, `lookup` returns
`Ok(values)`, where `values` is a list of all values for the key. The order is
unspecified; do not assume insertion order:

```gleam
let assert Ok(colors) = bag.lookup(table, key: "color")
// Contains each stored color once, in an unspecified order

// Returns an empty list if the key does not exist
let assert Ok([]) = bag.lookup(table, key: "nonexistent")

// Check if a key exists
let assert Ok(True) = bag.member(table, key: "color")
```

## Deleting data

Remove the color group, then recreate it to show how to remove just one color:

```gleam
// Delete all values for a key
let assert Ok(Nil) = bag.delete_key(table, key: "color")

// Delete a specific key-value pair, preserving other values for the key
let assert Ok(Nil) = bag.insert(table, "color", "red")
let assert Ok(Nil) = bag.insert(table, "color", "blue")
let assert Ok(Nil) = bag.delete_object(table, key: "color", value: "red")
let assert Ok(["blue"]) = bag.lookup(table, key: "color")
```

## Iterating over entries

Blue and the three food entries remain under three keys. A bag counts
entries, not distinct keys, so the fold and `size` both return 4:

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

The deletes and inserts above are not necessarily on disk yet. When they must
be on disk before you continue, call `sync`. It writes pending updates without
closing the table:

```gleam
let assert Ok(Nil) = bag.sync(table)
// Pending updates are written to disk; the table remains open
```

## Table info

`info` reports the same entry count as `size`, together with the size and
location of the file:

```gleam
let assert Ok(info) = bag.info(table)
// info.file_size - size of the file on disk in bytes
// info.object_count - number of entries, not distinct keys
// info.file_path - absolute path of the table file
```

`file_path` uses the normalized path from `open`; it does not resolve symlinks.
For the 2.0 record change, see [migration guidance](/advanced/stability/).

## Closing the table

You are done with the table, so close the handle. Closing writes all pending
updates to disk:

```gleam
let assert Ok(Nil) = bag.close(table)
```

Closing alone keeps the four entries for the next open. To discard all entries
instead, call `bag.delete_all(table)` before closing.

## Opening with options

The data is now in `data/tags.dets`. When you open the file again, you can
also select a repair policy and an access mode.

### Repair policy

A file that did not close cleanly can need repair. Make a backup before you repair a file with data you need to keep. Repair does not guarantee recovery of all data. See [Repair policies](/advanced/troubleshooting/#repair-policies) to choose an option.

```gleam
import slate.{AutoRepair, ForceRepair, NoRepair}
import gleam/dynamic/decode

let assert Ok(table) = bag.open_with(path: "data/tags.dets", repair: AutoRepair,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = bag.close(table)
```

### Access mode

To read the saved tags without a risk of changing the file, open it with
`ReadOnly`. This mode prevents writes through the table handle, and the file
must exist:

```gleam
import slate.{AutoRepair, ReadOnly}
import gleam/dynamic/decode

let assert Ok(table) = bag.open_with_access(path: "data/tags.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(["blue"]) = bag.lookup(table, key: "color")
// bag.insert(table, "color", "red") would return Error(AccessDenied(context))
let assert Ok(Nil) = bag.close(table)
```
