---
title: Bag Tables
description: Multiple distinct values per key with DETS bag tables.
---

Bag tables allow storing multiple values for the same key. Duplicate key-value pairs are silently ignored — if you insert the same key-value pair twice, only one copy is kept. Use [duplicate bag tables](/guides/duplicate-bag-tables/) if you need to store identical pairs.

Bag tables are provided by the `slate/bag` module and correspond to the `bag` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Opening and closing

```gleam
import slate/bag

let assert Ok(table) = bag.open("data/tags.dets")

// ... use the table ...

let assert Ok(Nil) = bag.close(table)
```

For safer lifecycle management, use [`with_table`](/advanced/with-table/) instead.

## Inserting data

```gleam
// Insert key-value pairs — multiple values per key are allowed
let assert Ok(Nil) = bag.insert(table, "color", "red")
let assert Ok(Nil) = bag.insert(table, "color", "blue")

// Duplicate pairs are silently ignored
let assert Ok(Nil) = bag.insert(table, "color", "red")
// Still only ["red", "blue"] for the "color" key

// Batch insert
let assert Ok(Nil) = bag.insert_list(table, [
  #("fruit", "apple"),
  #("fruit", "banana"),
  #("veggie", "carrot"),
])
```

## Looking up data

Unlike set tables, `lookup` returns a `List` of all values for the key:

```gleam
let assert Ok(colors) = bag.lookup(table, key: "color")
// colors == ["red", "blue"]

// Returns an empty list if the key doesn't exist
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
// Get all entries as a list
let assert Ok(entries) = bag.to_list(table)

// Fold over entries
let assert Ok(count) = bag.fold(table, from: 0, with: fn(acc, _key, _value) {
  acc + 1
})

// Get the number of stored objects
let assert Ok(n) = bag.size(table)
```

## Table info

```gleam
let assert Ok(info) = bag.info(table)
// info.file_size — size of the file on disk in bytes
// info.object_count — number of entries
// info.kind — slate.Bag
```

## Opening with options

### Repair policy

```gleam
import slate.{AutoRepair, ForceRepair, NoRepair}

let assert Ok(table) = bag.open_with("data/tags.dets", AutoRepair)
```

### Access mode

```gleam
import slate.{AutoRepair, ReadOnly}

let assert Ok(table) = bag.open_with_access("data/tags.dets", AutoRepair, ReadOnly)
```

## When to use bag tables

Bag tables are ideal when you need to associate multiple distinct values with a single key:

- **Tags and categories**: Map items to multiple tags
- **Indexes**: Build secondary indexes over your data
- **One-to-many relationships**: Users to roles, posts to comments
- **Grouping**: Collect related items under a common key
