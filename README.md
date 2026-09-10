<img src="https://slate.tylerbutler.com/slate.webp" alt="slate logo" width="200">

# slate

[![Package Version](https://img.shields.io/hexpm/v/slate)](https://hex.pm/packages/slate)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/slate/)

Type-safe Gleam wrapper for Erlang [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage).

DETS stores key-value pairs in files. Stored data persists across node restarts. An abnormal node shutdown can lose pending writes and leave the file needing repair. DETS is built into OTP. No separate database service is required.

> [!IMPORTANT]
> **Erlang target only.** slate does not support the JavaScript target.

## When to use DETS

| Approach | Setup | Persistence | Query capability |
|----------|-----------|-------------|------------------|
| JSON file | File I/O and serialization | Yes | None |
| **DETS** | **Included in OTP; add slate for Gleam** | **Yes** | **Key lookup, fold** |
| SQLite | Embedded database library | Yes | Full SQL |
| Postgres | Database server | Yes | Full SQL |
| Mnesia | Included in OTP; configure a schema | Yes | Key lookup, query expressions |

Use DETS when you need persistent key lookup without SQL or distributed storage.

## Installation

```sh
gleam add slate
```

## Usage

An entry is one key-value pair. The examples use files in a `data` directory.
Create it before you run them; slate does not create parent directories:

```sh
mkdir -p data
```

### Set tables (one value per key)

```gleam
import gleam/dynamic/decode
import slate/set

pub fn main() {
  // Open or create a table
  let assert Ok(users) = set.open("data/users.dets",
    key_decoder: decode.string, value_decoder: decode.int)

  // Insert key-value pairs
  let assert Ok(Nil) = set.insert(users, "alice", 42)
  let assert Ok(Nil) = set.insert(users, "bob", 37)

  // Look up values
  let assert Ok(age) = set.lookup(users, key: "alice")
  // age == 42

  // Check membership
  let assert Ok(True) = set.member(users, key: "alice")
  let assert Ok(False) = set.member(users, key: "charlie")

  // Always close when done
  let assert Ok(Nil) = set.close(users)
}
```

<a id="safe-table-lifecycle-with-with_table"></a>

### Open and close tables with `with_table`

```gleam
import gleam/dynamic/decode
import slate
import slate/set

pub fn main() {
  // Attempt to close the table after the callback returns
  let assert Ok(Nil) = set.with_table("data/config.dets",
    repair: slate.AutoRepair, access: slate.ReadWrite,
    key_decoder: decode.string, value_decoder: decode.string,
    callback: fn(table) {
      set.insert(table, "theme", "dark")
    })
}
```

Use `with_table` for short-lived operations. Select the repair policy and access
mode for each call. The callback must return a `Result`. If the callback succeeds
but closing fails, the helper returns the close error. If both fail, it returns
the callback error. If the callback raises, the helper attempts cleanup before
re-raising the exception. A forced process termination can prevent helper cleanup.

DETS tracks the processes that open a table and normally closes it when the last
user closes it or exits. An abnormal node shutdown can leave the file needing
repair.

For read-only access without automatic repair:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

use table <- set.with_table(
  path: "data/config.dets", repair: slate.NoRepair, access: slate.ReadOnly,
  key_decoder: decode.string, value_decoder: decode.string)
set.lookup(table, key: "theme")
```

`ReadOnly` requires an existing file. This helper is available in all three
table modules.

**Migrating from 1.x:** `with_table` now requires `repair` and `access`.
Add `repair: slate.AutoRepair` and `access: slate.ReadWrite` to keep the previous
behavior. Cleanup and error handling are unchanged.

### Bag tables (multiple values per key)

```gleam
import gleam/dynamic/decode
import slate/bag

pub fn main() {
  let assert Ok(tags) = bag.open("data/tags.dets",
    key_decoder: decode.string, value_decoder: decode.string)

  let assert Ok(Nil) = bag.insert(tags, "color", "red")
  let assert Ok(Nil) = bag.insert(tags, "color", "blue")

  let assert Ok(colors) = bag.lookup(tags, key: "color")
  // Contains "red" and "blue" in an unspecified order

  let assert Ok(Nil) = bag.close(tags)
}
```

### Duplicate bag tables

```gleam
import gleam/dynamic/decode
import slate/duplicate_bag

pub fn main() {
  let assert Ok(events) = duplicate_bag.open("data/events.dets",
    key_decoder: decode.string, value_decoder: decode.string)

  let assert Ok(Nil) = duplicate_bag.insert(events, "click", "button_a")
  let assert Ok(Nil) = duplicate_bag.insert(events, "click", "button_a")

  let assert Ok(clicks) = duplicate_bag.lookup(events, key: "click")
  // Contains two "button_a" values; lookup does not guarantee an order

  let assert Ok(Nil) = duplicate_bag.close(events)
}
```

### Data persists across restarts

```gleam
import gleam/dynamic/decode
import slate/set

pub fn write() {
  let assert Ok(table) = set.open("data/state.dets",
    key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "counter", 42)
  let assert Ok(Nil) = set.close(table)
}

pub fn read() {
  let assert Ok(table) = set.open("data/state.dets",
    key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(42) = set.lookup(table, key: "counter")
  let assert Ok(Nil) = set.close(table)
}
```

### Error handling

Most public operations return `Result(_, slate.DetsError)`.

`slate/set.update_counter` returns `Result(_, set.UpdateCounterError)`.
This type includes `set.CounterValueNotInteger` without adding a counter-specific
variant to `DetsError`.

The `error_code` and `error_message` helpers return strings. Exceptions raised by
your callbacks propagate through `with_table`, `fold`, and `fold_results`.

Match on the specific variants you expect in normal flows, and use the helper
functions when you want a stable code or a user-facing message:

```gleam
import slate
import slate/set

case set.lookup(table, key: "missing") {
  Ok(value) -> Ok(value)
  Error(slate.NotFound) -> Ok(default_value)
  Error(error) -> {
    let code = slate.error_code(error)
    let message = slate.error_message(error)
    // log code/message here
    Error(error)
  }
}
```

`UnexpectedError(detail)` is intended for diagnostics only; the detail string is
not a stable API contract, and `error_message` intentionally returns a generic
message for that variant.

When opening existing files, `Error(slate.NotADetsFile(context))` means the path is
readable but not a DETS file, and `Error(slate.NeedsRepair(context))` means the file was
not closed cleanly and you opened it with `NoRepair`.

File-related errors include `FileErrorContext(path: Option(String), reason: String)`.
The path comes from OTP; `None` means OTP supplied no single filename. The reason
retains lower-level diagnostics, including nested OTP reasons. Both fields are
for trusted diagnostics only and can contain sensitive data. `error_code` and
`error_message` do not include these details.

**Breaking migration:** `FileNotFound`, `AlreadyOpen`, `AccessDenied`, `TypeMismatch`,
`NeedsRepair`, `NotADetsFile`, and `FileSizeLimitExceeded` now require context.
Change patterns such as `Error(slate.AccessDenied)` to
`Error(slate.AccessDenied(_))`, or bind `context` to inspect it. See the
[migration guide](docs/file-error-context-migration.md) for before/after examples,
including code that constructs errors. No DETS file migration is needed.

For `set.update_counter`, match `Error(set.CounterValueNotInteger)` directly and
unwrap shared table failures as `Error(set.TableError(error))`.

## API overview

The three table types (`set`, `bag`, `duplicate_bag`) share a common core API:

| Function | Description |
|----------|-------------|
| `open(path, key_decoder, value_decoder)` | Open or create a table |
| `open_with(path, repair, key_decoder, value_decoder)` | Open with repair policy |
| `open_with_access(path, repair, access, key_decoder, value_decoder)` | Open with repair and access mode |
| `close(table)` | Close and flush to disk |
| `sync(table)` | Flush without closing |
| `with_table(path, repair, access, key_decoder, value_decoder, fn)` | Auto-closing callback with repair and access options |
| `insert(table, key, value)` | Insert a key-value pair |
| `insert_list(table, entries)` | Batch insert |
| `lookup(table, key)` | Get value(s) for key |
| `member(table, key)` | Check if key exists |
| `delete_key(table, key)` | Remove by key |
| `delete_object(table, key, value)` | Remove a specific key-value pair (`duplicate_bag` removes all exact duplicates) |
| `delete_all(table)` | Clear all entries |
| `to_list(table)` | Get all entries |
| `fold(table, acc, fn)` | Fold over entries |
| `fold_results(table, acc, fn)` | Fold over entries and handle decode errors in the callback |
| `size(table)` | Count entries |
| `info(table)` | Get the file size in bytes, entry count, and absolute file path |

Use `info(table)` to retrieve the file path from an open handle:

```gleam
let assert Ok(info) = set.info(table)
info.file_path
```

**Migrating from 1.x:** `TableInfo` now has a `file_path: String` field.
Supply it when constructing the record. Include the third field, or use `..`,
when matching the constructor. Existing `info.file_size` and
`info.object_count` access remains valid.

`slate/set` also provides:

| Function | Description |
|----------|-------------|
| `insert_new(table, key, value)` | Insert if key is absent |
| `update_counter(table, key, amount)` | Atomic counter increment |

`slate/bag` also provides:

| Function | Description |
|----------|-------------|
| `insert_new(table, key, value)` | Return an error if the exact key-value pair exists |

Concurrent `bag.insert_new` calls can both return `Ok(Nil)` for the same pair.
The table still stores one copy. To ensure only one caller reports a new
insertion, serialize writes through an owner process.

Bag and duplicate bag lookups return values in an unspecified order.
A duplicate bag does not enforce append-only access. Store a timestamp or
sequence number if you need to reconstruct event order.

`size` counts entries, not distinct keys. Each duplicate copy counts as an entry.
`info.file_size` is the file size in bytes; `info.object_count` is the entry count.

The top-level `slate` module also provides:

| Function | Description |
|----------|-------------|
| `is_dets_file(path)` | Check if a file is a valid DETS file |
| `error_code(error)` | Stable machine-readable error code |
| `error_message(error)` | User-facing error message |

## Limitations

- Each table has a 2 GB file size limit.
- DETS supports `set`, `bag`, and `duplicate_bag`, but not `ordered_set`.
- Disk-backed access is slower than ETS for frequent reads.
- Close tables after use. `with_table` attempts cleanup when the callback returns or raises.
- The internal table name pool is bounded. Opening too many distinct tables at once can fail with `TableNamePoolExhausted`. Close unused tables to release their slots.
- slate supports only Gleam's Erlang target.

By default, DETS saves a table after three minutes without table access.
Call `sync` and handle its result when you need to write pending updates to disk
before continuing.

Make a backup before you repair a file with data you need to keep. Repair does
not guarantee recovery of all data. Handle `NeedsRepair` separately from missing
files, permission failures, and other open errors.

## Stability

slate follows [Semantic Versioning](https://semver.org/). The **public API** covered by semver guarantees consists of four modules:

- `slate`: Shared types (`DetsError`, `FileErrorContext`, `AccessMode`, `RepairPolicy`, `TableInfo`) and helpers
- `slate/set`: Set tables
- `slate/bag`: Bag tables
- `slate/duplicate_bag`: Duplicate bag tables

The Erlang FFI files (`slate_dets_ffi.erl`, `slate_with_table_ffi.erl`) are internal implementation details and are **not** part of the public API. They may change in any release without notice.

**Versioning policy:** patch releases contain bug fixes only, minor releases add backward-compatible features, and major releases may include breaking changes. The `error_code()` strings returned by `slate.error_code` are stable across minor and patch releases and are safe for programmatic matching (e.g., in error-handling logic or logging). The `error_message()` strings are human-readable and may change in any release.

See [CHANGELOG.md](CHANGELOG.md) for release history and upgrade notes, and the [GitHub Releases](https://github.com/tylerbutler/slate/releases) page for tagged versions.

## Related projects

- [bravo](https://github.com/Michael-Mark-Edu/bravo) provides ETS bindings for Gleam.
- [shelf](https://github.com/tylerbutler/shelf) provides persistent ETS tables backed by DETS. It uses slate for disk storage and ETS for in-memory reads.

For details on the underlying storage engine, see the [Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Development

See [DEV.md](DEV.md) for setup instructions, build tasks, and contribution guidelines.

## License

MIT
