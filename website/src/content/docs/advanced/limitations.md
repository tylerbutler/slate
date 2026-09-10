---
title: Limitations
description: Known limitations of DETS and slate.
---

slate wraps Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html).
Use these limits to decide whether it fits your storage needs.

## File size limit

DETS limits each table file to **2 GB**. You cannot configure this limit.
A write that would exceed it returns `Error(FileSizeLimitExceeded(context))`.

:::tip
If you need more than 2 GB of storage, split data across tables or use a
database such as SQLite or Postgres.
:::

## No `ordered_set` table type

Unlike Erlang's ETS (in-memory storage), DETS does not support `ordered_set` tables. Only `set`, `bag`, and `duplicate_bag` are available. Keys are stored in an unspecified order.

<a id="disk-io-on-every-operation"></a>

## Disk-backed performance

DETS stores data on disk. Performance depends on disk I/O, buffering, and your
workload. A successful insert does not mean that the data has been
synchronously flushed to disk. Use `sync` to flush pending writes and `close`
when you finish with a table. Handle errors from both operations.

For frequent reads with low latency, load data into ETS at startup and use
DETS for persistence.

:::note
The related library [shelf](https://github.com/tylerbutler/shelf) provides
ETS tables backed by DETS. Reads use memory. Persistence still depends on
when writes reach disk.
:::

## Tables must be closed properly

VM or node termination and power loss can prevent a DETS table from closing
properly. Pending writes may be lost, and the file may need repair on the
next open. File persistence does not guarantee that all writes survive a crash.

Keep primary data files on persistent storage and maintain backups. Deleting
or replacing a DETS file loses the data in that file.

An individual Erlang process exit is different. DETS tracks processes that
open a table and normally closes it when the last user exits.
[`with_table`](/advanced/with-table/) attempts to close the table after its
callback returns or raises. The helper cannot run cleanup after a forced kill
of the owning process. For longer-lived tables, call `close` yourself.

slate's default `AutoRepair` policy attempts repair when needed. `ForceRepair`
repairs even a properly closed file. `NoRepair` returns `NeedsRepair` when
repair is required. None of these policies guarantees full data recovery.
Back up a closed file before attempting repair.

## Erlang target only

DETS is a BEAM feature. slate supports only Gleam's Erlang target.
It does not support the JavaScript target.

## Bounded table-name pool

slate reuses a pool of 4096 DETS table names instead of creating an atom for
each path. Up to 4096 distinct normalized paths can be open at once.
Closing a table releases its slot for reuse. If all slots are in use,
new opens for other paths return `TableNamePoolExhausted`.

## No concurrent access from multiple OS processes

Open each DETS file from only one OS process at a time. Multiple Erlang
processes within that BEAM node can share the table. Opening the same file
from separate BEAM nodes or OS processes can corrupt it.

## Validating DETS files

Use `slate.is_dets_file` to identify a DETS file before opening it:

```gleam
import slate

let assert Ok(True) = slate.is_dets_file("data/cache.dets")
let assert Ok(False) = slate.is_dets_file("README.md")
```

Use this when scanning a directory for DETS files. A result of `Ok(True)`
does not guarantee file integrity, successful decoding, or safe access to
a user-provided path. Apply your application's path and access rules separately.

## Comparison with alternatives

<table class="slate-comparison">
  <caption class="sr-only">DETS compared with other BEAM storage options</caption>
  <thead>
    <tr>
      <th scope="col">Feature</th>
      <th scope="col">DETS (slate)</th>
      <th scope="col">ETS</th>
      <th scope="col">SQLite</th>
      <th scope="col">Mnesia</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Persistence</td>
      <td data-label="DETS (slate)">Disk</td>
      <td data-label="ETS">Memory only</td>
      <td data-label="SQLite">Disk</td>
      <td data-label="Mnesia">Memory or disk, depending on table configuration</td>
    </tr>
    <tr>
      <td>Maximum size</td>
      <td data-label="DETS (slate)">2 GB per file</td>
      <td data-label="ETS">RAM</td>
      <td data-label="SQLite">Depends on configuration and storage</td>
      <td data-label="Mnesia">Depends on table type, configuration, and storage</td>
    </tr>
    <tr>
      <td>Query capability</td>
      <td data-label="DETS (slate)">Key lookup, fold</td>
      <td data-label="ETS">Key lookup, match specs</td>
      <td data-label="SQLite">Full SQL</td>
      <td data-label="Mnesia">Match specs, QLC</td>
    </tr>
    <tr>
      <td>Ordered keys</td>
      <td data-label="DETS (slate)">No</td>
      <td data-label="ETS">Yes (<code>ordered_set</code>)</td>
      <td data-label="SQLite">Yes</td>
      <td data-label="Mnesia">Yes</td>
    </tr>
    <tr>
      <td>Storage engine</td>
      <td data-label="DETS (slate)">Included in OTP</td>
      <td data-label="ETS">Included in OTP</td>
      <td data-label="SQLite">Separate library</td>
      <td data-label="Mnesia">Included in OTP</td>
    </tr>
    <tr>
      <td>Performance</td>
      <td data-label="DETS (slate)">Depends on disk I/O and workload</td>
      <td data-label="ETS">In-memory reads</td>
      <td data-label="SQLite">Depends on workload</td>
      <td data-label="Mnesia">Depends on configuration and workload</td>
    </tr>
    <tr>
      <td>Concurrent processes</td>
      <td data-label="DETS (slate)">Single node</td>
      <td data-label="ETS">Single node</td>
      <td data-label="SQLite">Multiple</td>
      <td data-label="Mnesia">Distributed</td>
    </tr>
  </tbody>
</table>
