<img src="https://slate.tylerbutler.com/slate.webp" alt="slate logo" width="200">

# slate

[![Package Version](https://img.shields.io/hexpm/v/slate)](https://hex.pm/packages/slate)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/slate/)

Type-safe Gleam wrapper for Erlang [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage).

Some programs must keep data after they stop, but do not need a database
server. DETS is for these programs. It is part of OTP, and it keeps key-value
pairs in a file on disk. slate gives Gleam typed access to those files:
decoders check each value that you read, and each operation returns a `Result`.

The file keeps your data across node restarts. But an abnormal shutdown can
lose pending writes and leave the file needing repair. For this reason, the
examples below also show how to close tables safely.

> [!IMPORTANT]
> **Erlang target only.** DETS is part of the BEAM, so slate does not support
> the JavaScript target.

## When to use DETS

DETS is between a plain file and a full database:

| Approach | Setup | Persistence | Query capability |
|----------|-----------|-------------|------------------|
| JSON file | File I/O and serialization | Yes | None |
| **DETS** | **Included in OTP; add slate for Gleam** | **Yes** | **Key lookup, fold** |
| SQLite | Embedded database library | Yes | Full SQL |
| Postgres | Database server | Yes | Full SQL |
| Mnesia | Included in OTP; configure a schema | Yes | Key lookup, query expressions |

Use DETS when you need persistent key lookup without SQL or distributed storage.
If you need queries, or more than 2 GB in one table, use a database instead.
See [Limitations](#limitations).

## Installation

```sh
gleam add slate
```

slate requires Gleam 1.14+ and OTP 26+. For native components, source builds,
and escript delivery, see the [installation guide](https://slate.tylerbutler.com/installation/).

## Usage

The examples follow one small program. It stores users' ages, then tags,
then click events. Each table is a file in a `data` directory. slate does not
create parent directories, so create the directory first:

```sh
mkdir -p data
```

All of these examples assume that only one BEAM VM uses each file.

> [!WARNING]
> If independent BEAM VMs share a file, use exclusive sessions for every read
> and write. The unlocked examples here do not coordinate across VMs;
> simultaneous access can lose writes or damage the file. See
> [exclusive sessions](#exclusive-sessions-across-cli-processes).

### Set tables (one value per key)

Start with a set, which keeps one value for each key. Here, each user has one
age. A key and its value make one entry. `with_table` opens the file, runs your
callback, and attempts to close the table before it returns:

```gleam
import gleam/dynamic/decode
import gleam/result
import slate
import slate/set

pub fn main() -> Result(Int, slate.DetsError) {
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
```

Gleam's `use` syntax passes the rest of the block as a callback, and
`result.try` returns early if an insert fails. Thus `main` returns `Ok(42)`
only if the inserts, the lookup, and the close all succeed. `gleam run` does
not print the return value; the [quick start](https://slate.tylerbutler.com/quick-start/)
adds visible output.

### Data persists across restarts

The ages are in a file, so a new VM can read them. Stop the program and open
the same file again. This time, open it read-only and without automatic
repair, so that the read cannot change the file:

```gleam
import gleam/dynamic/decode
import slate
import slate/set

pub fn main() -> Result(Int, slate.DetsError) {
  use users <- set.with_table(
    path: "data/users.dets", repair: slate.NoRepair, access: slate.ReadOnly,
    key_decoder: decode.string, value_decoder: decode.int)
  set.lookup(users, key: "alice")
}
```

The result is `Ok(42)` again, from the file and not from memory. `ReadOnly`
requires an existing file. If the file was not closed cleanly, `NoRepair`
returns `NeedsRepair` and does not change the file. The
[quick start](https://slate.tylerbutler.com/quick-start/) runs both programs
and prints the result in each VM.

<a id="safe-table-lifecycle-with-with_table"></a>

### Open and close tables with `with_table`

Both programs depend on `with_table` to close the file. Closing is important:
it writes pending updates to disk, and a table that is not closed can need
repair. The callback must return a `Result`, and the helper handles each way
that the callback can end:

- If the callback succeeds but closing fails, it returns the close error.
- If the callback returns an error, it returns that error, even if closing
  also fails.
- If the callback raises, it attempts cleanup and then re-raises the exception.

Each call selects a repair policy and an access mode. The helper is available
in all three table modules.

The helper cannot prevent all problems. A forced termination of the process
can stop its cleanup. DETS also tracks the processes that open a table, and
it normally closes the table when the last user closes it or exits. But an
abnormal node shutdown can still leave the file needing repair.

For long-lived tables, such as a cache in a server, call `open` and `close`
yourself. See the [table cleanup guide](https://slate.tylerbutler.com/advanced/with-table/).

### Bag tables (multiple values per key)

Users also have tags, and one key can need several values. A bag keeps
several distinct values for each key. This example and the next one call
`open` and `close` directly, which is the manual style for long-lived tables.
If you insert the same pair again, the bag keeps one copy:

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

A bag removes repeated pairs, but some data must keep them. If a user clicks
the same button two times, you want to count two clicks. A duplicate bag keeps
each occurrence as a separate entry:

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

Lookups do not keep insertion order, and a duplicate bag does not enforce
append-only access. To reconstruct the order of events, store a timestamp or
sequence number with each value.

### Exclusive sessions across CLI processes

Up to this point, only one VM uses each file. Now think of a CLI that keeps a
cache in DETS: two runs of the same command are two VMs, and they can open the
file at the same time. The warning at the start of [Usage](#usage) applies
to this case.

`with_exclusive_table` prevents this problem. It acquires an OS lock before
it opens or repairs DETS, runs your callback, and then closes DETS before it
releases the lock. The lock is advisory, so it works only if every client uses
it, including readers. APIs that do not use exclusive sessions, raw DETS, and
older slate versions ignore the lock.

Obey these rules to keep a session safe:

- Keep the handle and all table work inside the callback. Do not reopen or
  close the table yourself.
- Callback errors do not undo writes.
- Keep paths in a trusted, stable directory.
- Do not delete or replace the persistent `<resolved-path>.slate.lock` sidecar
  while clients can start sessions.

If cleanup is not safe, a session can keep ownership until the VM exits.

The OS lock uses a native component that Hex releases include. This component
requires a supported OS, architecture, and local filesystem. Source checkouts
need Rust/Cargo 1.91 and `just native-build`. Only exclusive sessions load native
code. See [native delivery and escripts](https://slate.tylerbutler.com/installation/#exclusive-session-native-component).

The helper is available for all three table types. The
[exclusive-session guide](https://slate.tylerbutler.com/advanced/exclusive-sessions/)
shows a CLI cache pattern, acquisition waits, errors, recovery, path
restrictions, and measured open/close costs.

### Error handling

The examples above stop at the first error, with `result.try` or `let assert`.
A real program must decide what to do with each error. Most operations return
`Result(_, slate.DetsError)`. Match the variants that you expect in normal
flows. For other errors, `slate.error_code` gives a stable code and
`slate.error_message` gives a user-facing message:

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

When you open an existing file, two errors tell you about the file itself.
`Error(slate.NotADetsFile(context))` means that the path is readable but is not
a DETS file. `Error(slate.NeedsRepair(context))` means that the file was not
closed cleanly and you opened it with `NoRepair`.

File-related errors include `FileErrorContext(path: Option(String), reason: String)`.
The path comes from OTP; `None` means that OTP supplied no single filename.
The reason keeps lower-level diagnostics, including nested OTP reasons. Both
fields are for trusted diagnostics only and can contain sensitive data.
For this reason, `error_code` and `error_message` do not include them.
In the same way, `UnexpectedError(detail)` is for diagnostics only. Its detail
string is not a stable API contract, and `error_message` returns a generic
message for it.

Two operations can fail in ways that `DetsError` does not describe, so they
use their own error types:

- `set.update_counter` returns `Result(_, set.UpdateCounterError)`. Match
  `Error(set.CounterValueNotInteger)` directly, and unwrap shared table
  failures as `Error(set.TableError(error))`.
- `with_exclusive_table` returns `Result(_, exclusive.SessionError)`. Use
  `exclusive.error_code` and `exclusive.error_message` for these errors.
  The callback still returns `Result(_, slate.DetsError)`.

Exceptions are different from errors. If your callback raises, the exception
propagates through `with_table`, `fold`, and `fold_results`.

## API overview

The three table types (`set`, `bag`, `duplicate_bag`) share a common core API.
Code that you write for one table type looks the same for the others:

| Function | Description |
|----------|-------------|
| `open(path, key_decoder, value_decoder)` | Open or create a table |
| `open_with(path, repair, key_decoder, value_decoder)` | Open with repair policy |
| `open_with_access(path, repair, access, key_decoder, value_decoder)` | Open with repair and access mode |
| `close(table)` | Close and flush to disk |
| `sync(table)` | Flush without closing |
| `with_table(path, repair, access, key_decoder, value_decoder, fn)` | Auto-closing callback with repair and access options |
| `with_exclusive_table(path, repair, access, wait, key_decoder, value_decoder, fn)` | Cross-process exclusive callback, closed before unlock |
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

`size` counts entries, not distinct keys, so each duplicate copy counts.
`info` returns that count as `info.object_count`, the file size in bytes as
`info.file_size`, and the path of the open file as `info.file_path`:

```gleam
let assert Ok(info) = set.info(table)
info.file_path
```

Each table type also has functions that only its rules make possible.
`slate/set` keeps one value per key, so it can check for a key or count with it:

| Function | Description |
|----------|-------------|
| `insert_new(table, key, value)` | Insert if key is absent |
| `update_counter(table, key, amount)` | Atomic counter increment |

`slate/bag` keeps distinct pairs, so it can check for a pair:

| Function | Description |
|----------|-------------|
| `insert_new(table, key, value)` | Return an error if the exact key-value pair exists |

Concurrent `bag.insert_new` calls can both return `Ok(Nil)` for the same pair.
The table still stores one copy. To make sure that only one caller reports a
new insertion, send writes through one owner process.

The top-level `slate` module provides helpers for files and errors:

| Function | Description |
|----------|-------------|
| `is_dets_file(path)` | Check if a file is a valid DETS file |
| `error_code(error)` | Stable machine-readable error code |
| `error_message(error)` | User-facing error message |

## Limitations

DETS is simple because it does less than a database. Check these limits before
you select it:

- Each table has a 2 GB file size limit.
- DETS supports `set`, `bag`, and `duplicate_bag`, but not `ordered_set`.
- Disk-backed access is slower than ETS for frequent reads.
- Close tables after use. `with_table` attempts cleanup when the callback returns or raises.
- The internal table name pool is bounded. Opening too many distinct tables at once can fail with `TableNamePoolExhausted`. Close unused tables to release their slots.
- slate supports only Gleam's Erlang target.
- Independent VMs must use exclusive sessions for every access to a shared file.
  Simultaneous unlocked access can lose writes or damage the file. Exclusive
  sessions require qualified local storage; network filesystems are unsupported.

Within one VM, slate gives you more safety than raw DETS. It coordinates writes
to each table. Counter validation and increment share that coordination with
inserts and deletes, so a rejected noninteger counter stays unchanged. Reads
and operations on other tables stay independent. Raw `dets:*` writes bypass
this coordination. It does not replace exclusive sessions across VMs, and it
does not provide multi-operation transactions.

slate also prevents a new open from using a file that an old DETS process can
still write. It keeps a VM-wide reservation for each active table path until
the DETS process and pending opens finish. A close caller's death does not
release that reservation while the file can still be written. If the private
lifetime service fails, new opens return `UnexpectedError`, but existing reads
and cleanup closes stay available. Restart the VM to recover. Do not restart an
empty lifetime service or hot-upgrade from an older implementation while table
work is active. A stuck native open or close can block later work on the same
path.

A successful write is not always on disk yet. By default, DETS saves a table
after three minutes without table access. When you must write pending updates
to disk before you continue, call `sync` and handle its result.

If a file needs repair, be careful with it. Make a backup before you repair a
file with data you need to keep, because repair does not guarantee recovery of
all data. Handle `NeedsRepair` separately from missing files, permission
failures, and other open errors.

## Stability

slate follows [Semantic Versioning](https://semver.org/). The **public API** covered by semver guarantees consists of five modules:

- `slate`: Shared types (`DetsError`, `FileErrorContext`, `AccessMode`, `RepairPolicy`, `TableInfo`) and helpers
- `slate/set`: Set tables
- `slate/bag`: Bag tables
- `slate/duplicate_bag`: Duplicate bag tables
- `slate/exclusive`: Acquisition waits, session errors, and safe classifiers

The Erlang FFI files and native lock implementation are internal details and are
**not** part of the public API. They may change in any release without notice.

**Versioning policy:** patch releases contain bug fixes only, minor releases add backward-compatible features, and major releases may include breaking changes. The `error_code()` strings returned by `slate.error_code` are stable across minor and patch releases and are safe for programmatic matching (e.g., in error-handling logic or logging). The `error_message()` strings are human-readable and may change in any release.

See [CHANGELOG.md](CHANGELOG.md) for release history and upgrade notes, and the [GitHub Releases](https://github.com/tylerbutler/slate/releases) page for tagged versions.

## Upgrading from 1.x

slate 2.0 changed three parts of the API. You must change your code, but your
DETS files need no migration.

- **`with_table` options:** `with_table` requires `repair` and `access`.
  Add `repair: slate.AutoRepair` and `access: slate.ReadWrite` to keep the
  previous behavior. Cleanup and error handling are unchanged.
- **File error context:** `FileNotFound`, `AlreadyOpen`, `AccessDenied`,
  `TypeMismatch`, `NeedsRepair`, `NotADetsFile`, and `FileSizeLimitExceeded`
  now require context. Change patterns such as `Error(slate.AccessDenied)` to
  `Error(slate.AccessDenied(_))`, or bind `context` to inspect it. The
  [migration guide](docs/file-error-context-migration.md) has before/after
  examples, including code that constructs errors.
- **`TableInfo` file path:** `TableInfo` has a `file_path: String` field.
  Supply it when you construct the record. Include the third field, or use `..`,
  when you match the constructor. Existing `info.file_size` and
  `info.object_count` access stays valid.

## Related projects

- [bravo](https://github.com/Michael-Mark-Edu/bravo) provides ETS bindings for Gleam.
- [shelf](https://github.com/tylerbutler/shelf) provides persistent ETS tables backed by DETS. It uses slate for disk storage and ETS for in-memory reads.

For details on the underlying storage engine, see the [Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Development

See [DEV.md](DEV.md) for setup instructions, build tasks, and contribution guidelines.

## Software bills of materials

Hex packages include CycloneDX 1.6 JSON inventories alongside the native libraries:

- `priv/sbom/slate-gleam.cdx.json`: Slate's locked Gleam dependencies.
- `priv/sbom/slate-native.cdx.json`: The native library's locked Rust dependencies.

GitHub Releases provide the same documents as `slate-gleam.cdx.json` and
`slate-native.cdx.json`. Release qualification creates detached signed GitHub
attestations for these files; the JSON contains no embedded signatures.
Verify an extracted or downloaded document with:

```sh
gh attestation verify path/to/slate-gleam.cdx.json --repo tylerbutler/slate \
  --signer-workflow tylerbutler/slate/.github/workflows/ci.yml
```

See [DEV.md](DEV.md#software-bills-of-materials) for inventory coverage and
the original-byte checks used for release recovery.

## License

MIT
