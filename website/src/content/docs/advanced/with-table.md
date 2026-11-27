---
title: Open and close tables with with_table
description: Use with_table to close tables after short-lived operations.
---

DETS keeps recent writes in memory and saves them later, at the latest when
the table closes. If the VM stops before the table closes, those writes can be
lost, and the file can need repair on the next open. Thus each open needs a
matching close, even when an operation fails between them.

`with_table` makes the close part of the call. It opens a table, runs your
callback, and attempts to close the table when the callback ends. The callback
must return `Result(a, DetsError)`. If it raises an exception, `with_table`
attempts cleanup and then re-raises the exception.

The examples on this page follow one program, which keeps its settings in
`data/config.dets`.

:::caution
`with_table` cannot run cleanup after a forced kill of the owning process.
In that case, DETS itself usually closes the table: it tracks the processes
that open a table and closes it when the last user exits. An abnormal node
shutdown can still leave the file needing repair.
:::

`with_table` does not acquire an OS lock. For a file shared by independent
BEAM VMs, use [`with_exclusive_table`](/advanced/exclusive-sessions/) for every
read and write.

## Basic usage

The program saves the user's theme. With a manual lifecycle, the close runs
only if every step before it succeeds:

```gleam
import gleam/dynamic/decode
import slate/set

// Manual lifecycle: close might not be called if an error occurs
let assert Ok(table) = set.open("data/config.dets",
  key_decoder: decode.string, value_decoder: decode.string)
let assert Ok(Nil) = set.insert(table, "theme", "dark")
let assert Ok(Nil) = set.close(table)
```

With `with_table`, the close runs however the callback ends:

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

An explicit `callback:` function gets hard to read as the work grows. Gleam's
`use` syntax passes the rest of the block as the callback instead. The callback
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

The previous example returns the theme from the callback. `with_table` returns
`Result(a, DetsError)`, and it passes on the callback's `Ok(value)` only if
closing also succeeds. If the callback succeeds but closing fails, it returns
the close error instead. Thus `Ok("dark")` below means that the insert, the
lookup, and the close all succeeded:

```gleam
import gleam/dynamic/decode
import gleam/result
import slate
import slate/set

let assert Ok(theme) = set.with_table("data/config.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) {
    use Nil <- result.try(set.insert(table, "theme", "dark"))
    set.lookup(table, key: "theme")
  })
// theme == "dark"
```

## Error handling

A callback can also fail. Suppose the program asks for a setting that it
never saved. The callback returns an `Error`, and `with_table` attempts to
close the table. It returns the callback error even if closing also fails, so
this result does not confirm that closing succeeded:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let result = set.with_table("data/config.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) {
    set.lookup(table, key: "font_size")
  })
// If the key is absent, result is Error(NotFound) after attempted cleanup
```

A callback can also raise instead of returning. A `let assert` raises if its
pattern does not match, and `panic` always raises. In both cases, `with_table`
attempts to close the table before it re-raises the original exception:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let _ = set.with_table("data/config.dets",
  repair: slate.AutoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) {
    let assert Ok(Nil) = set.insert(table, "theme", "light")
    panic as "boom"
  })
```

Finally, the open itself can fail. For example, the file can need repair after
a crash, and `NoRepair` refuses to repair it. Then `with_table` returns the open
error and does not call the callback:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

let result = set.with_table("data/config.dets",
  repair: slate.NoRepair, access: slate.ReadWrite,
  key_decoder: decode.string, value_decoder: decode.string,
  callback: fn(table) {
    set.lookup(table, key: "theme")
  })
// If opening fails, result contains that error and the callback does not run
```

## Available on all table types

The settings file is a set, but the same helper exists in all three table
modules. These examples return the entry count after closing each table:

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

Every example on this page passes `repair` and `access`, because `with_table`
requires both. Select them for each call. For example, to read the saved theme
without a risk of changing the file, use `NoRepair` and `ReadOnly`:

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

## When to use `with_table`

The settings program opens its file for one short task at a time. That is the
case that `with_table` fits best.

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
| File shared by independent CLI processes | `with_exclusive_table` |
| Long-running server with a persistent cache | `open` / `close` |
| Multiple operations across time | `open` / `close` |

## Migrating from 1.x

In 2.0, `with_table` requires repair and access options in all three table modules.
Add `repair: slate.AutoRepair` and `access: slate.ReadWrite` to existing calls
to keep their previous behavior. Cleanup and error precedence are unchanged.

The callback argument label is `callback:` instead of `fun:`. Change explicit
`fun: fn(table) { ... }` arguments to `callback: fn(table) { ... }`.
This label rename does not affect positional callback arguments or `use` syntax.
