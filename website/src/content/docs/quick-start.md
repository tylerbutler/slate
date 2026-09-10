---
title: Quick start
description: Create a table, write values, and read them back.
---

This guide creates a typed table, writes two values, reads one back, and closes the table automatically.

## 1. Add slate to your project

```bash
gleam add slate
```

## 2. Open a table and store data

Create the `data` directory in your project before you run the example. slate creates table files, but it does not create parent directories.

```sh
mkdir -p data
```

Use this code in your application's main module:

```gleam
import gleam/dynamic/decode
import gleam/result
import slate
import slate/set

pub fn main() {
  use users <- set.with_table(
    "data/users.dets",
    repair: slate.AutoRepair,
    access: slate.ReadWrite,
    key_decoder: decode.string,
    value_decoder: decode.int,
  )
  use Nil <- result.try(set.insert(users, "alice", 42))
  use Nil <- result.try(set.insert(users, "bob", 37))
  set.lookup(users, key: "alice")
}
// Ok(42), and the table is closed
```

`use users <- set.with_table(...)` passes the rest of `main` as a callback. `with_table` opens the file before it calls the callback and attempts to close it when the callback returns. The key decoder accepts strings; the value decoder accepts integers. Reads return a decode error if the stored data does not match the expected types.

`main` returns `Ok(42)` if the operations and close succeed. `gleam run` does not print this return value.

## 3. Data persists across restarts

```gleam
import gleam/dynamic/decode
import slate
import slate/set

pub fn write() {
  use table <- set.with_table(
    "data/state.dets",
    repair: slate.AutoRepair,
    access: slate.ReadWrite,
    key_decoder: decode.string,
    value_decoder: decode.int,
  )
  set.insert(table, "counter", 42)
}

pub fn read() {
  use table <- set.with_table(
    "data/state.dets",
    repair: slate.AutoRepair,
    access: slate.ReadWrite,
    key_decoder: decode.string,
    value_decoder: decode.int,
  )
  set.lookup(table, key: "counter")
}
```

Call `write` and confirm that it returns `Ok(Nil)`. Stop the node, then call `read` from the same working directory. It returns `Ok(42)` from the same file.

An abnormal node shutdown can lose pending writes and leave the file needing repair. See the [table cleanup guide](/advanced/with-table/) for cleanup and repair options.

## Next steps

- Use [set tables](/guides/set-tables/) for one value per key
- Use [bag tables](/guides/bag-tables/) for multiple distinct values per key
- Use [duplicate bag tables](/guides/duplicate-bag-tables/) to store repeated key-value pairs
- Use [`with_table`](/advanced/with-table/) for short-lived operations that close on return
