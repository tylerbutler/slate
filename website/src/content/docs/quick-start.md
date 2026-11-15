---
title: Quick start
description: Create a table, write values, and read them back.
---

Store two users' ages, print one age, then read it again in a new BEAM VM. Each run closes the table before it exits.

## 1. Add slate to your project

```bash
gleam add slate
```

## 2. Open a table and store data

Create the `data` directory in your project before you run the example. slate creates table files, but it does not create parent directories.

```sh
mkdir -p data
```

Replace the contents of your application's main module with this code:

```gleam
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/result
import slate
import slate/set

pub fn main() -> Nil {
  let lookup = {
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
  case lookup {
    Ok(age) -> io.println("Alice's age: " <> int.to_string(age))
    Error(error) -> io.println(slate.error_message(error))
  }
}
```

`use users <- set.with_table(...)` passes the rest of the inner block as a callback. `with_table` opens the file before it calls the callback and attempts to close it when the callback returns. The key decoder accepts strings; the value decoder accepts integers. Reads return a decode error if the stored data does not match the expected types. `result.try` returns early from the callback if an insert fails.

From your project directory, run:

```sh
gleam run
```

If the inserts, lookup, and close succeed, the program prints:

```text
Alice's age: 42
```

The program prints an error message if a storage operation fails.

## 3. Read the data in a new VM

The first run has exited and closed its table. Replace your main module with
this read-only version to check the saved data without inserting it again:

```gleam
import gleam/dynamic/decode
import gleam/int
import gleam/io
import slate
import slate/set

pub fn main() -> Nil {
  let lookup = {
    use users <- set.with_table(
      "data/users.dets",
      repair: slate.NoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
    set.lookup(users, key: "alice")
  }
  case lookup {
    Ok(age) -> io.println("Alice's age: " <> int.to_string(age))
    Error(error) -> io.println(slate.error_message(error))
  }
}
```

Run `gleam run` again from the same project directory. This starts a new BEAM VM.
You should see `Alice's age: 42` again: the program read it from
`data/users.dets`, not from the first VM's memory.

`ReadOnly` requires an existing file, and `NoRepair` reports a repair requirement
without changing the file. An abnormal node shutdown can lose pending writes
and leave the file needing repair. See the [table cleanup guide](/advanced/with-table/)
for cleanup and repair options.

## Next steps

- Use [set tables](/guides/set-tables/) for one value per key
- Use [bag tables](/guides/bag-tables/) for multiple distinct values per key
- Use [duplicate bag tables](/guides/duplicate-bag-tables/) to store repeated key-value pairs
- Choose cleanup and repair options with [`with_table`](/advanced/with-table/)

If independent CLI processes share a file, use
[exclusive sessions](/advanced/exclusive-sessions/) for every read and write.
The `with_table` calls above do not acquire an OS lock.
