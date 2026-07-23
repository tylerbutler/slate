---
title: What is slate?
description: An introduction to slate and DETS.
---

slate gives Gleam programs typed access to Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage). It keeps DETS's file-backed storage model while replacing dynamic Erlang terms and exceptions with explicit Gleam types and `Result` values.

## The BEAM storage layer you already have

DETS ships with OTP. It stores Erlang terms on disk, supports key lookup and folds, and survives node restarts without a separate database service.

That makes it useful when a serialized file is too limited but SQLite, Postgres, or Mnesia would add more operational weight than the application needs. The trade-offs are real: DETS has a 2 GB table limit, performs disk I/O on every operation, and is not a distributed database. See [Limitations](/advanced/limitations/) for the complete boundary.

## How slate maps DETS into Gleam

- **Typed table handles:** `slate/set`, `slate/bag`, and `slate/duplicate_bag` expose the same operations without allowing table types to be mixed accidentally.
- **Decoding at the storage boundary:** You provide key and value decoders when opening a table. Reads return a decode error if the data on disk does not match those types.
- **Explicit failures:** Public operations return `Result` values instead of raising Erlang exceptions.
- **Managed short-lived access:** `with_table` opens a table, runs your callback, and closes the table before returning.
- **Stable public API:** slate 1.0 is covered by the documented [semver guarantees](/advanced/stability/).

## Gleam idioms in the examples

If you are coming from Erlang or Elixir, two patterns appear frequently:

- `use table <- set.with_table(...)` is callback shorthand. The remainder of the block becomes the callback that receives `table`.
- `decode.string`, `decode.int`, and other decoders describe the types slate should accept when reading Erlang terms from disk.

The [Quick Start](/quick-start/) puts those pieces together in a complete read-and-write example.

## Choose a table type

- Use a [set table](/guides/set-tables/) when each key has one value.
- Use a [bag table](/guides/bag-tables/) when each key can have several distinct values.
- Use a [duplicate bag table](/guides/duplicate-bag-tables/) when repeated key-value pairs must be preserved.

## Related BEAM storage projects

- **[bravo](https://github.com/Michael-Mark-Edu/bravo)** — Comprehensive ETS (in-memory) bindings for Gleam. Use bravo when you need fast, in-memory storage without persistence.
- **[shelf](https://github.com/tylerbutler/shelf)** — Persistent ETS tables backed by DETS. Combines microsecond in-memory reads with durable disk storage. Built on top of slate.

## Underlying DETS behavior

slate does not replace DETS semantics. For storage-engine details beyond slate's API, see the [official Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).
