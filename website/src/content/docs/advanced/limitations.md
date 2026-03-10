---
title: Limitations
description: Known limitations of DETS and slate.
---

slate wraps Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html), which has several inherent limitations. Understanding these helps you choose the right storage approach.

## File size limit

DETS tables are limited to **2 GB** per file. This is a hard limit in the DETS implementation and cannot be configured. If a table exceeds this size, operations will return `Error(FileSizeLimitExceeded)`.

:::tip
If you need more than 2 GB of storage, consider splitting data across multiple tables, or using a database like SQLite or Postgres.
:::

## No `ordered_set` table type

Unlike Erlang's ETS (in-memory storage), DETS does not support `ordered_set` tables. Only `set`, `bag`, and `duplicate_bag` are available. Keys are stored in an unspecified order.

## Disk I/O on every operation

DETS performs disk I/O on every read and write. This makes it unsuitable for high-frequency operations where latency matters. For performance-critical reads, consider loading data into ETS at startup and using DETS only for persistence.

:::note
The related library [shelf](https://github.com/tylerbutler/shelf) automates this pattern — it provides persistent ETS tables backed by DETS, giving you microsecond reads with durable storage.
:::

## Tables must be closed properly

If a DETS table is not closed properly (e.g., due to a crash), pending writes may be lost and the file may need repair on the next open. Use [`with_table`](/advanced/with-table/) for short-lived operations to ensure tables are always closed.

By default, slate uses `AutoRepair`, which automatically repairs improperly closed tables. You can also use `ForceRepair` to always repair, or `NoRepair` to return an error instead.

## Erlang target only

DETS is a BEAM feature. slate only works with Gleam's **Erlang target** — there is no JavaScript target support.

## Atom exhaustion

DETS table names are derived from the file path, converted to an Erlang atom. Erlang atoms are never garbage collected, so each unique file path permanently consumes an atom. This is rarely a problem in practice, but avoid opening tables with dynamically generated paths in a loop.

## No concurrent access from multiple OS processes

A DETS file should only be opened by a single OS process at a time. Multiple Erlang processes within the same BEAM node can share a table, but opening the same file from separate BEAM nodes or OS processes can lead to corruption.

## Validating DETS files

Use `slate.is_dets_file` to check whether a file on disk is a valid DETS file before opening it:

```gleam
import slate

let assert Ok(True) = slate.is_dets_file("data/cache.dets")
let assert Ok(False) = slate.is_dets_file("README.md")
```

This is useful when scanning a directory for DETS files or validating user-provided paths.

## Comparison with alternatives

| Feature | DETS (slate) | ETS | SQLite | Mnesia |
|---------|-------------|-----|--------|--------|
| Persistence | ✅ Disk | ❌ Memory only | ✅ Disk | ✅ Disk |
| Max size | 2 GB | RAM | Unlimited | Unlimited |
| Query capability | Key lookup, fold | Key lookup, match specs | Full SQL | Match specs, QLC |
| Ordered keys | ❌ | ✅ (ordered_set) | ✅ | ✅ |
| External dependency | None (OTP built-in) | None (OTP built-in) | Yes | None (OTP built-in) |
| Performance | Disk I/O bound | Microseconds | Varies | Varies |
| Concurrent processes | Single node | Single node | Multiple | Distributed |
