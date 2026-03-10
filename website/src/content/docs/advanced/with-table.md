---
title: Safe Resource Management
description: Using with_table for automatic table lifecycle management.
---

DETS tables must be properly closed to ensure data is flushed to disk. If a table is not closed — for example, because an error occurs — pending writes may be lost and the file may need repair on next open.

The `with_table` function solves this by automatically closing the table when your callback returns, whether it succeeds or fails.

## Basic usage

Instead of manually opening and closing:

```gleam
import slate/set

// ❌ Manual lifecycle — close might not be called if an error occurs
let assert Ok(table) = set.open("data/config.dets")
let assert Ok(Nil) = set.insert(table, "theme", "dark")
let assert Ok(Nil) = set.close(table)
```

Use `with_table`:

```gleam
import slate/set

// ✅ Table is automatically closed when the callback returns
let assert Ok(Nil) = set.with_table("data/config.dets", fn(table) {
  set.insert(table, "theme", "dark")
})
```

## Using `use` syntax

Gleam's `use` syntax makes `with_table` even cleaner:

```gleam
import slate/set

let result = {
  use table <- set.with_table("data/config.dets")
  let assert Ok(Nil) = set.insert(table, "theme", "dark")
  set.lookup(table, key: "theme")
}
// table is closed here, regardless of the result
```

## Return values

`with_table` returns whatever your callback returns:

```gleam
import slate/set

let assert Ok(age) = set.with_table("data/users.dets", fn(table) {
  let assert Ok(Nil) = set.insert(table, "alice", 42)
  set.lookup(table, key: "alice")
})
// age == 42
```

## Error handling

If the callback returns an `Error`, the table is still closed:

```gleam
import slate/set

let result = set.with_table("data/users.dets", fn(table) {
  set.lookup(table, key: "nonexistent")
})
// result == Error(NotFound), and the table has been closed
```

If the table itself fails to open, the error is returned immediately:

```gleam
import slate.{NoRepair}
import slate/set

let result = set.with_table("corrupted.dets", fn(table) {
  set.lookup(table, key: "key")
})
// result == Error(...) from the open failure
```

## Available on all table types

`with_table` is available on all three table types:

```gleam
import slate/set
import slate/bag
import slate/duplicate_bag

let assert Ok(_) = set.with_table("data/set.dets", fn(table) { ... })
let assert Ok(_) = bag.with_table("data/bag.dets", fn(table) { ... })
let assert Ok(_) = duplicate_bag.with_table("data/dup.dets", fn(table) { ... })
```

## Repair and access options

`with_table` always opens the table with `AutoRepair` and `ReadWrite` access. If you need a different repair policy or read-only access, use `open_with` or `open_with_access` directly and manage the lifecycle yourself.

## When to use `with_table`

:::tip
Use `with_table` for short-lived operations — lookups, inserts, or quick computations. For long-lived tables that stay open for the lifetime of your application, use `open`/`close` directly and manage the lifecycle yourself.
:::

| Scenario | Recommended |
|----------|-------------|
| Quick lookup or insert | `with_table` |
| Script that reads/writes once | `with_table` |
| Long-running server with a persistent cache | `open` / `close` |
| Multiple operations across time | `open` / `close` |
