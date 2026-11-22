---
title: What is slate?
description: An introduction to slate and DETS.
---

Some programs must keep data after they stop, but do not need a database server. Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage) is for these programs, and slate makes it available to Gleam with types. slate stores data in DETS files, uses decoders to check the data that you read, and returns `Result` values for storage errors.

<a id="the-beam-storage-layer-you-already-have"></a>

## Storage built into OTP

DETS ships with OTP, so you do not install or run a separate database service. It stores Erlang terms on disk and supports key lookup and folds.

That is enough for many programs, but not all. Use DETS when you need persistent key lookup without SQL or distributed storage. Each table has a 2 GB file size limit, and disk-backed access is slower than ETS for frequent reads. Also, an abnormal node shutdown can lose pending writes and leave the file needing repair. See [Limitations](/advanced/limitations/).

## How slate maps DETS into Gleam

DETS accepts any Erlang term, so a file can contain data that your program does not expect. slate adds types in two places to protect you.

First, each table type has its own handle type in the `slate/set`, `slate/bag`, and `slate/duplicate_bag` modules. Thus you cannot pass a bag to a set operation. The modules share a core API. Set and bag tables also provide `insert_new`, with different duplicate rules. Only set tables provide `update_counter`.

Second, you provide key and value decoders when you open a table. Reads return a decode error if the stored data does not match the expected types. Opening a table does not check all its entries, so a bad entry shows only when you read it.

Types do not close files, so slate also gives you `with_table` for short-lived access. It opens a table, runs your callback, and attempts to close the table before it returns. Exceptions raised by your callback propagate to the caller. See the [table cleanup guide](/advanced/with-table/) for error handling.

## Gleam idioms in the examples

If you come from Erlang or Elixir, two patterns in the examples can look new:

- `use table <- set.with_table(...)` is callback shorthand. The remainder of the block becomes the callback that receives `table`.
- `decode.string`, `decode.int`, and other decoders describe the types slate should accept when reading Erlang terms from disk.

The [quick start](/quick-start/) uses both patterns to store users' ages, print a value, and read it again in a new BEAM VM.

## Choose a table type

After the quick start, select the table type that matches the shape of your data:

- Use a [set table](/guides/set-tables/) when each key has one value.
- Use a [bag table](/guides/bag-tables/) when each key can have several distinct values.
- Use a [duplicate bag table](/guides/duplicate-bag-tables/) when repeated key-value pairs must be preserved.

## Related BEAM storage projects

If DETS is not the right fit, these projects cover nearby needs:

- [bravo](https://github.com/Michael-Mark-Edu/bravo) provides ETS bindings for Gleam. Use it for in-memory storage without persistence.
- [shelf](https://github.com/tylerbutler/shelf) provides persistent ETS tables backed by DETS. It uses slate for disk storage and ETS for in-memory reads.

## Underlying DETS behavior

slate does not replace DETS semantics. For storage-engine details beyond slate's API, see the [official Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).
