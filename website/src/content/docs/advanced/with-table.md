---
title: Open and close tables with with_table
description: Use with_table to close tables after short-lived operations.
---

Close DETS tables to flush pending writes to disk. If the VM stops before a
table closes, pending writes may be lost. The file may need repair on the next
open.

`with_table` opens a table, runs your callback, and attempts to close the table.
The callback must return `Result(a, DetsError)`. If it raises an exception,
`with_table` attempts cleanup and then re-raises the exception.

:::caution
`with_table` cannot run cleanup after a forced kill of the owning process.
DETS tracks processes that open a table and normally closes it when its last
user exits. This is separate from helper cleanup. Select the repair policy
and access mode for each call.
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

// Ok(Nil) means the insert and close both succeeded
let assert Ok(Nil) = set.with_table("data/config.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) {
    set.insert(table, "theme", "dark")
  })
```

## Using `use` syntax

Gleam's `use` syntax passes the rest of the block as the callback. The callback
receives the table and returns the block's final result:

```gleam
import gleam/dynamic/decode
import gleam/result
import slate
import slate/set

let result = {
  use table <- set.with_table("data/config.dets",
    repair: slate.AutoRepair, access: slate.ReadWrite,
    key_decoder: decode.string, value_decoder: decode.string)
  use Nil <- result.try(set.insert(table, "theme", "dark"))
  set.lookup(table, key: "theme")
}
// with_table has attempted to close the table before returning result
```

## Return values

`with_table` returns `Result(a, DetsError)`. It returns the callback's `Ok(value)`
only if closing also succeeds. If the callback succeeds but closing fails,
it returns the close error.

```gleam
import gleam/dynamic/decode
import gleam/result
import slate
import slate/set

let assert Ok(age) = set.with_table("data/users.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.int,
  callback: fn(table) {
    use Nil <- result.try(set.insert(table, "alice", 42))
    set.lookup(table, key: "alice")
  })
// age == 42
```

## Error handling

If the callback returns an `Error`, `with_table` attempts to close the table.
It returns the callback error even if closing also fails. This result does
not confirm that closing succeeded:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let result = set.with_table("data/users.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.int,
  callback: fn(table) {
    set.lookup(table, key: "nonexistent")
  })
// If the key is absent, result is Error(NotFound) after attempted cleanup
```

If the callback raises, `with_table` attempts to close the table before it
re-raises the original exception. A `let assert` also raises if its pattern
does not match:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let _ = set.with_table("data/users.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.int,
  callback: fn(table) {
    let assert Ok(Nil) = set.insert(table, "alice", 42)
    panic as "boom"
  })
```

If opening fails, `with_table` returns the open error without calling the
callback:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let result = set.with_table("corrupted.dets",
  repair: slate.NoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) {
    set.lookup(table, key: "key")
  })
// If opening fails, result contains that error and the callback does not run
```

## Available on all table types

`with_table` is available on all three table types. These examples return
the entry count after closing each table:

```gleam
import gleam/dynamic/decode
import slate
import slate/set
import slate/bag
import slate/duplicate_bag

let assert Ok(_) = set.with_table("data/set.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) { set.size(table) })
let assert Ok(_) = bag.with_table("data/bag.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) { bag.size(table) })
let assert Ok(_) = duplicate_bag.with_table("data/dup.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) { duplicate_bag.size(table) })
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

In 2.0, `with_table` requires repair and access options in all three table modules.
Add `repair: slate.AutoRepair` and `access: slate.ReadWrite` to existing calls
to keep their previous behavior. Cleanup and error precedence are unchanged.

The callback argument label is `callback:` instead of `fun:`. Change explicit
`fun: fn(table) { ... }` arguments to `callback: fn(table) { ... }`.
This label rename does not affect positional callback arguments or `use` syntax.

## When to use `with_table`

:::tip
Use `with_table` for short-lived lookups, inserts, or computations with the
repair and access options you need. For long-lived tables, use `open`/`close`
and manage the lifecycle yourself.
:::

| Scenario | Recommended |
|----------|-------------|
| Quick lookup or insert | `with_table` |
| Script that reads or writes once | `with_table` |
| Short-lived read-only access or a specific repair policy | `with_table` |
| Long-running server with a persistent cache | `open` / `close` |
| Multiple operations across time | `open` / `close` |
