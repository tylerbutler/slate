---
title: Quick Start
description: Get up and running with slate in minutes.
---

This guide creates a typed table, writes two values, reads one back, and closes the table automatically.

## 1. Add slate to your project

```bash
gleam add slate
```

## 2. Open a table and store data

```gleam
import gleam/dynamic/decode
import gleam/result
import slate/set

pub fn main() {
  use users <- set.with_table(
    "data/users.dets",
    key_decoder: decode.string,
    value_decoder: decode.int,
  )
  use Nil <- result.try(set.insert(users, "alice", 42))
  use Nil <- result.try(set.insert(users, "bob", 37))
  set.lookup(users, key: "alice")
}
// Ok(42), and the table is closed
```

`use users <- set.with_table(...)` passes the rest of `main` as a callback. `with_table` opens the file before that callback and closes it when the callback returns. The decoders make reads fail explicitly if the terms on disk are not strings and integers.

## 3. Data persists across restarts

```gleam
import gleam/dynamic/decode
import slate/set

pub fn write() {
  use table <- set.with_table(
    "data/state.dets",
    key_decoder: decode.string,
    value_decoder: decode.int,
  )
  set.insert(table, "counter", 42)
}

pub fn read() {
  use table <- set.with_table(
    "data/state.dets",
    key_decoder: decode.string,
    value_decoder: decode.int,
  )
  set.lookup(table, key: "counter")
}
```

Run `write`, stop the node, then run `read`: it returns `Ok(42)` from the same file.

## Next steps

- Learn about [Set Tables](/guides/set-tables/) for unique key-value storage
- Use [Bag Tables](/guides/bag-tables/) for multiple values per key
- Explore [Duplicate Bag Tables](/guides/duplicate-bag-tables/) for allowing duplicates
- Use [`with_table`](/advanced/with-table/) for short-lived operations that close on return
