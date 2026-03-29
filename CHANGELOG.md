# Changelog


## v0.1.0 - 2026-03-29


#### Added

##### Initial release of slate, a type-safe Gleam wrapper for Erlang DETS (Disk Erlang Term Storage).

### Table types

- **Set** (`slate/set`) — one value per key; insert overwrites
- **Bag** (`slate/bag`) — multiple distinct values per key; `insert` returns
  `Error(KeyAlreadyPresent)` for duplicate key-value pairs, while `insert_list`
  silently deduplicates (native DETS behavior)
- **Duplicate bag** (`slate/duplicate_bag`) — allows duplicate key-value pairs

### Operations

All three table types share a consistent API surface:

- `open`, `open_with`, `open_with_access` — open or create a table with configurable
  repair policy and access mode
- `close`, `sync` — flush writes and close, or flush without closing
- `with_table` — open a table within a callback, guaranteeing close afterward
  (including when the callback raises an exception)
- `insert`, `insert_new`, `insert_list` — write operations
- `lookup`, `member`, `to_list`, `fold`, `size` — read operations
- `delete_key`, `delete_object`, `delete_all` — delete operations
- `update_counter` — atomic integer increment (set tables only)
- `info` — file size, object count, and table kind
- `is_dets_file` — check if a file is a valid DETS file

### Type safety

All table-opening functions require `key_decoder` and `value_decoder` parameters.
Data read from disk is validated against expected Gleam types at runtime. A
`DecodeErrors(List(decode.DecodeError))` variant on `DetsError` is returned when
stored data doesn't match the expected types.

```gleam
import gleam/dynamic/decode
import slate/set

let assert Ok(table) = set.open("cache.dets",
  key_decoder: decode.string, value_decoder: decode.int)
let assert Ok(42) = set.lookup(table, "hits")
```

### Error handling

All public functions return `Result` types. The `DetsError` type covers:
`NotFound`, `KeyAlreadyPresent`, `FileNotFound`, `AccessDenied`, `TypeMismatch`,
`AlreadyOpen`, `FileSizeLimitExceeded`, `TableDoesNotExist`, `DecodeErrors`,
and `ErlangError`.

### Configuration

- Repair policies: `AutoRepair`, `ForceRepair`, `NoRepair`
- Access modes: `ReadWrite`, `ReadOnly`

### Limitations

- Erlang target only
- 2 GB maximum file size per table
- Bounded table-name pool (4096 slots) — at most 4096 distinct tables can be
  open concurrently
- Disk I/O on every operation — not suitable for high-frequency reads
- Tables must be closed properly; use `with_table` to avoid leaking handles


