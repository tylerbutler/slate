---
title: Safe Resource Management
description: Using with_table for short-lived table lifecycle management.
---

DETS tables must be properly closed to ensure data is flushed to disk. If a table is not closed — for example, because an error occurs — pending writes may be lost and the file may need repair on next open.

`with_table` helps with short-lived operations by opening a table, running your callback, and closing the table before it returns. If the callback raises, `with_table` still attempts to close the table before re-raising the exception.

:::caution
`with_table` cannot close the table if the owning process is terminated before
cleanup runs. Select the repair policy and access mode for each call.
:::

## Basic usage

Instead of manually opening and closing:

```gleam
import gleam/dynamic/decode
import slate/set

// Manual lifecycle: close might not be called if an error occurs
let assert Ok(table) = set.open("data/config.dets",
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = set.insert(table, "theme", "dark")
let assert Ok(Nil) = set.close(table)
```

Use `with_table`:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

// The table is closed when the callback completes
let assert Ok(Nil) = set.with_table("data/config.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) {
    set.insert(table, "theme", "dark")
  })
```

## Using `use` syntax

Gleam's `use` syntax makes `with_table` even cleaner:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let result = {
  use table <- set.with_table("data/config.dets",
    repair: slate.AutoRepair, access: slate.ReadWrite,
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
import slate
import slate/set

let assert Ok(age) = set.with_table("data/users.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
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
import slate
import slate/set

let result = set.with_table("data/users.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.int,
  fun: fn(table) {
    set.lookup(table, key: "nonexistent")
  })
// result == Error(NotFound), and the table has been closed
```

If the callback raises, `with_table` still attempts to close the table before re-raising:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let _ = set.with_table("data/users.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.int,
  fun: fn(table) {
    let assert Ok(Nil) = set.insert(table, "alice", 42)
    panic as "boom"
  })
```

If the table itself fails to open, the error is returned immediately:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let result = set.with_table("corrupted.dets",
  repair: slate.NoRepair, access: slate.ReadWrite,
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
import slate
import slate/set
import slate/bag
import slate/duplicate_bag

let assert Ok(_) = set.with_table("data/set.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) { ... })
let assert Ok(_) = bag.with_table("data/bag.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) { ... })
let assert Ok(_) = duplicate_bag.with_table("data/dup.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  fun: fn(table) { ... })
```

## Repair and access options

Pass `repair` and `access` to `with_table`. For example, use `NoRepair` and
`ReadOnly` to read an existing table without automatic repair:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

use table <- set.with_table(
  path: "data/config.dets",
  repair: slate.NoRepair,
  access: slate.ReadOnly,
  key_decoder: decode.string,
  value_decoder: decode.string,
)
set.lookup(table, key: "theme")
```

`ReadOnly` requires an existing file. `NoRepair` returns `NeedsRepair` if the
file needs repair. The callback does not run if opening fails.

## Migrating from 1.x

`with_table` now requires repair and access options in all three table modules.
Add `repair: slate.AutoRepair` and `access: slate.ReadWrite` to existing calls
to keep their previous behavior. Cleanup and error precedence are unchanged.

## When to use `with_table`

:::tip
Use `with_table` for short-lived lookups, inserts, or computations with the
repair and access options you need. For long-lived tables, use `open`/`close`
and manage the lifecycle yourself.
:::

| Scenario | Recommended |
|----------|-------------|
| Quick lookup or insert | `with_table` |
| Script that reads/writes once | `with_table` |
| Short-lived read-only access or a specific repair policy | `with_table` |
| Long-running server with a persistent cache | `open` / `close` |
| Multiple operations across time | `open` / `close` |
