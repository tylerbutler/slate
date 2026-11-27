---
title: Duplicate bag tables
description: Tables that allow duplicate key-value pairs.
---

Duplicate bag tables work like [bag tables](/guides/bag-tables/) but store repeated copies of the same key-value pair. Each insert adds an entry, even if the pair exists.

Duplicate bag tables are provided by the `slate/duplicate_bag` module and correspond to the `duplicate_bag` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

<a id="when-to-use-duplicate-bag-tables"></a>

Use a duplicate bag to record repeated events or measurements and count their
occurrences with a fold. A bag would keep only one copy of two identical clicks;
a duplicate bag keeps both. The examples below record button clicks and errors.
Run the snippets in order within one function, keeping the handle open until
the closing step. The final options section shows separate ways to reopen
the saved file.

A duplicate bag keeps each event, but not the order of events. Store a timestamp
or sequence number with each value if you need to reconstruct that order. It
also does not enforce append-only access, so it is not an immutable audit log.

## Opening and closing

Create the parent directory before opening the table. Use a new file path if
`data/events.dets` already contains data. `open` uses `AutoRepair` and `ReadWrite`.

```gleam
import gleam/dynamic/decode
import slate/duplicate_bag

let assert Ok(table) = duplicate_bag.open("data/events.dets",
  key_decoder: decode.string, value_decoder: decode.string)
```

Keep `table` for the following operations. For short-lived application tasks,
use [`with_table`](/advanced/with-table/) to attempt cleanup when the callback returns.

## Inserting data

Record two clicks on button A and one on button B. Each click gets its own entry:

```gleam
// Each insert adds a new entry, even if the pair already exists
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_a")
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_a")
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_b")

// Batch insert
let assert Ok(Nil) = duplicate_bag.insert_list(table, [
  #("error", "timeout"),
  #("error", "timeout"),
  #("error", "connection_refused"),
])
```

## Looking up data

Read the clicks back. Both copies of the button A value remain, because
`lookup` returns `Ok(values)`, where `values` is a list of all values for the
key, including duplicates. The order is unspecified; do not assume insertion
order:

```gleam
let assert Ok(clicks) = duplicate_bag.lookup(table, key: "click")
// Contains two "button_a" values and one "button_b", in an unspecified order

// Returns an empty list if the key does not exist
let assert Ok([]) = duplicate_bag.lookup(table, key: "nonexistent")

// Check if a key exists
let assert Ok(True) = duplicate_bag.member(table, key: "click")
```

## Deleting data

Remove the clicks, then recreate them to show that `delete_object` removes
all copies of a matching pair:

```gleam
// Delete all values for a key
let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "click")

// Delete all occurrences of a specific key-value pair
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_a")
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_a")
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_b")
let assert Ok(Nil) = duplicate_bag.delete_object(table, key: "click", value: "button_a")
// Only "button_b" remains; both copies of "button_a" were removed
```

## Iterating over entries

One click and three error entries remain. Both timeout entries count toward
the total, so the fold and `size` both return 4:

```gleam
// Get all entries in an unspecified order (loads the entire table into memory)
let assert Ok(entries) = duplicate_bag.to_list(table)

// Fold over entries in an unspecified order, including duplicate copies
let assert Ok(count) = duplicate_bag.fold(table, from: 0, with: fn(acc, _key, _value) {
  acc + 1
})

// Count entries, not distinct keys; each duplicate copy counts as an entry
let assert Ok(n) = duplicate_bag.size(table)
```

## Flushing writes

The recorded events are not necessarily on disk yet. When they must be on
disk before you continue, call `sync`. It writes pending updates without
closing the table:

```gleam
let assert Ok(Nil) = duplicate_bag.sync(table)
// Pending updates are written to disk; the table remains open
```

## Table info

`info` reports the same entry count as `size`, together with the size and
location of the file:

```gleam
let assert Ok(info) = duplicate_bag.info(table)
// info.file_size - size of the file on disk in bytes
// info.object_count - number of entries, including duplicate copies
// info.file_path - absolute path of the table file
```

`file_path` uses the normalized path from `open`; it does not resolve symlinks.
For the 2.0 record change, see [migration guidance](/advanced/stability/).

## Closing the table

You are done with the table, so close the handle. Closing writes all pending
updates to disk:

```gleam
let assert Ok(Nil) = duplicate_bag.close(table)
```

Closing alone keeps the four events for the next open. To discard all entries
instead, call `duplicate_bag.delete_all(table)` before closing.

## Opening with options

The events are now in `data/events.dets`. When you open the file again, you
can also select a repair policy and an access mode.

### Repair policy

A file that did not close cleanly can need repair. Make a backup before you repair a file with data you need to keep. Repair does not guarantee recovery of all data. See [Repair policies](/advanced/troubleshooting/#repair-policies) to choose an option.

```gleam
import slate.{AutoRepair}
import gleam/dynamic/decode

let assert Ok(table) = duplicate_bag.open_with(path: "data/events.dets",
  repair: AutoRepair,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = duplicate_bag.close(table)
```

### Access mode

To read the saved events without a risk of changing the file, open it with
`ReadOnly`. This mode prevents writes through the table handle, and the file
must exist:

```gleam
import slate.{AutoRepair, ReadOnly}
import gleam/dynamic/decode

let assert Ok(table) = duplicate_bag.open_with_access(path: "data/events.dets",
  repair: AutoRepair, access: ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(["button_b"]) = duplicate_bag.lookup(table, key: "click")
// duplicate_bag.insert(table, "click", "button_a") would return Error(AccessDenied(context))
let assert Ok(Nil) = duplicate_bag.close(table)
```

<a id="bag-vs-duplicate-bag"></a>

## Compare bag and duplicate bag tables

The two bag types differ only in how they treat a repeated pair. If you
recorded these events in a bag, the second `button_a` click would disappear:

| Behavior | Bag | Duplicate bag |
|----------|-----|---------------|
| Same key, different values | Stored | Stored |
| Insert an existing pair | Keep one copy | Add another copy |
| `delete_object` removes | One pair | All copies of the pair |
