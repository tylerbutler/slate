---
title: Safe Resource Management
description: Using with_table for short-lived table lifecycle management.
---

DETS tables must be properly closed to ensure data is flushed to disk. If a table is not closed — for example, because an error occurs — pending writes may be lost and the file may need repair on next open.

`with_table` helps with short-lived operations by opening a table, running your callback, and closing the table before it returns. If the callback raises, `with_table` still attempts to close the table before re-raising the exception.

:::caution
`with_table` is a convenience helper, not a crash-proof lifecycle primitive. It always uses the default `AutoRepair` + `ReadWrite` open path, and it cannot close the table if the owning process is terminated before cleanup runs.
:::

## Basic usage

Instead of manually opening and closing:

```gleam
import gleam/dynamic/decode
import slate/set

// ❌ Manual lifecycle — close might not be called if an error occurs
let assert Ok(table) = set.open("data/config.dets",
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = set.insert(table, "theme", "dark")
let assert Ok(Nil) = set.close(table)
```

Use `with_table`:

```gleam
import gleam/dynamic/decode
import slate/set

// ✅ Table is closed when the callback completes
let assert Ok(Nil) = set.with_table("data/config.dets",
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) {
    set.insert(table, "theme", "dark")
  })
```

## Using `use` syntax

Gleam's `use` syntax makes `with_table` even cleaner:

```gleam
import gleam/dynamic/decode
import slate/set

let result = {
  use table <- set.with_table("data/config.dets",
    key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "theme", "dark")
  set.lookup(table, key: "theme")
}
// table is closed here once the block returns
```

## Return values

`with_table` returns whatever your callback returns:

```gleam
import gleam/dynamic/decode
import slate/set

let assert Ok(age) = set.with_table("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int,
  fun: fn(table) {
    let assert Ok(Nil) = set.insert(table, "alice", 42)
    set.lookup(table, key: "alice")
  })
// age == 42
```

## Error handling

If the callback returns an `Error`, `with_table` still attempts to close the table before returning the callback error:

```gleam
import gleam/dynamic/decode
import slate/set

let result = set.with_table("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int,
  fun: fn(table) {
    set.lookup(table, key: "nonexistent")
  })
// result == Error(NotFound), and the table has been closed
```

If the callback raises, `with_table` still attempts to close the table before re-raising:

```gleam
import gleam/dynamic/decode
import slate/set

let _ = set.with_table("data/users.dets",
  key_decoder: decode.string, value_decoder: decode.int,
  fun: fn(table) {
    let assert Ok(Nil) = set.insert(table, "alice", 42)
    panic as "boom"
  })
```

If the table itself fails to open, the error is returned immediately:

```gleam
import gleam/dynamic/decode
import slate/set

let result = set.with_table("corrupted.dets",
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) {
    set.lookup(table, key: "key")
  })
// result == Error(...) from the open failure
```

## Available on all table types

`with_table` is available on all three table types:

```gleam
import gleam/dynamic/decode
import slate/set
import slate/bag
import slate/duplicate_bag

let assert Ok(_) = set.with_table("data/set.dets",
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) { ... })
let assert Ok(_) = bag.with_table("data/bag.dets",
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) { ... })
let assert Ok(_) = duplicate_bag.with_table("data/dup.dets",
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) { ... })
```

## Repair and access options

`with_table` always opens the table with `AutoRepair` and `ReadWrite` access. If you need a different repair policy or read-only access, use `open_with` or `open_with_access` directly and manage the lifecycle yourself.

## When to use `with_table`

:::tip
Use `with_table` for short-lived operations — lookups, inserts, or quick computations where automatic cleanup around the callback is enough. For long-lived tables that stay open for the lifetime of your application, or when you need non-default repair/access options, use `open`/`close` directly and manage the lifecycle yourself.
:::

| Scenario | Recommended |
|----------|-------------|
| Quick lookup or insert | `with_table` |
| Script that reads/writes once | `with_table` |
| Long-running server with a persistent cache | `open` / `close` |
| Multiple operations across time | `open` / `close` |
