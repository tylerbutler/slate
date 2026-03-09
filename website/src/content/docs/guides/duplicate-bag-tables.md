---
title: Duplicate Bag Tables
description: Tables that allow duplicate key-value pairs.
---

Duplicate bag tables work like [bag tables](/guides/bag-tables/) but allow storing identical key-value pairs multiple times. Each insert adds a new copy, even if the exact same pair already exists.

Duplicate bag tables are provided by the `slate/duplicate_bag` module and correspond to the `duplicate_bag` table type in Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Opening and closing

```gleam
import slate/duplicate_bag

let assert Ok(table) = duplicate_bag.open("data/events.dets")

// ... use the table ...

let assert Ok(Nil) = duplicate_bag.close(table)
```

For safer lifecycle management, use [`with_table`](/advanced/with-table/) instead.

## Inserting data

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

Like bag tables, `lookup` returns a `List` of all values — including duplicates:

```gleam
let assert Ok(clicks) = duplicate_bag.lookup(table, key: "click")
// clicks == ["button_a", "button_a", "button_b"]

// Returns an empty list if the key doesn't exist
let assert Ok([]) = duplicate_bag.lookup(table, key: "nonexistent")

// Check if a key exists
let assert Ok(True) = duplicate_bag.member(table, key: "click")
```

## Deleting data

```gleam
// Delete all values for a key
let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "click")

// Delete all occurrences of a specific key-value pair
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_a")
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_a")
let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_b")
let assert Ok(Nil) = duplicate_bag.delete_object(table, key: "click", value: "btn_a")
// Only "btn_b" remains — both copies of "btn_a" were removed

// Clear all entries
let assert Ok(Nil) = duplicate_bag.delete_all(table)
```

## Iterating over entries

```gleam
// Get all entries as a list
let assert Ok(entries) = duplicate_bag.to_list(table)

// Fold over entries (includes duplicates)
let assert Ok(count) = duplicate_bag.fold(table, from: 0, with: fn(acc, _key, _value) {
  acc + 1
})

// Get the number of stored objects (includes duplicates)
let assert Ok(n) = duplicate_bag.size(table)
```

## Table info

```gleam
let assert Ok(info) = duplicate_bag.info(table)
// info.file_size — size of the file on disk in bytes
// info.object_count — number of entries (including duplicates)
// info.kind — slate.DuplicateBag
```

## Opening with options

### Repair policy

```gleam
import slate.{AutoRepair}

let assert Ok(table) = duplicate_bag.open_with("data/events.dets", AutoRepair)
```

### Access mode

```gleam
import slate.{AutoRepair, ReadOnly}

let assert Ok(table) = duplicate_bag.open_with_access("data/events.dets", AutoRepair, ReadOnly)
```

## Bag vs. Duplicate Bag

| Behavior | Bag | Duplicate Bag |
|----------|-----|---------------|
| Same key, different values | ✅ Stored | ✅ Stored |
| Same key, same value (duplicate pair) | ❌ Ignored | ✅ Stored |
| `delete_object` removes | One pair | All copies of the pair |

## When to use duplicate bag tables

Duplicate bag tables are ideal for append-only or event-style data:

- **Event logs**: Record every occurrence, even repeats
- **Audit trails**: Track all actions including duplicates
- **Time-series data**: Store repeated measurements
- **Counters by event**: Count occurrences by folding over entries
