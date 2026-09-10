---
title: What is slate?
description: An introduction to slate and DETS.
---

slate gives Gleam programs typed access to Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage). It stores data in DETS files and uses decoders to check the data you read. Table operations return `Result` values for storage errors.

<a id="the-beam-storage-layer-you-already-have"></a>

## Storage built into OTP

DETS ships with OTP. It stores Erlang terms on disk and supports key lookup and folds. No separate database service is required.

Use DETS when you need persistent key lookup without SQL or distributed storage. Each table has a 2 GB file size limit. Disk-backed access is slower than ETS for frequent reads. An abnormal node shutdown can lose pending writes and leave the file needing repair. See [Limitations](/advanced/limitations/).

## How slate maps DETS into Gleam

The `slate/set`, `slate/bag`, and `slate/duplicate_bag` modules share a core API. Each module has its own table-handle type, so you cannot pass a bag to a set operation. Set and bag tables also provide `insert_new`, with different duplicate rules. Only set tables provide `update_counter`.

You provide key and value decoders when opening a table. Reads return a decode error if the stored data does not match the expected types. Opening a table does not check all its entries.

Use `with_table` for short-lived access. It opens a table, runs your callback, and attempts to close the table before returning. Exceptions raised by your callback propagate to the caller. See the [table cleanup guide](/advanced/with-table/) for error handling.

slate follows the documented [Semantic Versioning policy](/advanced/stability/).

## Gleam idioms in the examples

If you are coming from Erlang or Elixir, two patterns appear frequently:

- `use table <- set.with_table(...)` is callback shorthand. The remainder of the block becomes the callback that receives `table`.
- `decode.string`, `decode.int`, and other decoders describe the types slate should accept when reading Erlang terms from disk.

The [quick start](/quick-start/) shows how to use both patterns to read and write data.

## Choose a table type

- Use a [set table](/guides/set-tables/) when each key has one value.
- Use a [bag table](/guides/bag-tables/) when each key can have several distinct values.
- Use a [duplicate bag table](/guides/duplicate-bag-tables/) when repeated key-value pairs must be preserved.

## Related BEAM storage projects

- [bravo](https://github.com/Michael-Mark-Edu/bravo) provides ETS bindings for Gleam. Use it for in-memory storage without persistence.
- [shelf](https://github.com/tylerbutler/shelf) provides persistent ETS tables backed by DETS. It uses slate for disk storage and ETS for in-memory reads.

## Underlying DETS behavior

slate does not replace DETS semantics. For storage-engine details beyond slate's API, see the [official Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).
