# slate

[![Package Version](https://img.shields.io/hexpm/v/slate)](https://hex.pm/packages/slate)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/slate/)

Type-safe Gleam wrapper for Erlang [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage).

> **Erlang target only** — DETS is a BEAM feature with no JavaScript target support.

DETS provides persistent key-value storage backed by files on disk. Tables survive process crashes and node restarts. DETS is built into OTP — no external database or dependency is needed.

## When to use DETS

| Approach | Complexity | Persistence | Query capability |
|----------|-----------|-------------|------------------|
| JSON file | Low | Yes | None |
| **DETS** | **Low** | **Yes** | **Key lookup, fold** |
| SQLite/Postgres | High | Yes | Full SQL |
| Mnesia | High | Yes | Transactions, distribution |

DETS fills the gap between "serialize to a file" and "add a database dependency."

## Installation

```sh
gleam add slate
```

## Usage

If you use `data/*.dets` paths from the examples, create the directory first:

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

### Safe table lifecycle with `with_table`

```gleam
import gleam/dynamic/decode
import slate/set

pub fn main() {
  // Table is closed after the callback returns
  let assert Ok(Nil) = set.with_table("data/config.dets",
    key_decoder: decode.string, value_decoder: decode.string,
    fun: fn(table) {
      set.insert(table, "theme", "dark")
    })
}
```

Use `with_table` for short-lived operations. It opens with the default
`AutoRepair` + `ReadWrite` settings, closes when the callback returns, and also
attempts cleanup if the callback raises. It still does not make DETS
crash-proof — if the owning process is terminated before cleanup runs, DETS may
still need repair on the next open.

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
  // colors == ["red", "blue"]

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
  // clicks == ["button_a", "button_a"]

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

## API Overview

All three table types (`set`, `bag`, `duplicate_bag`) share the same API surface:

| Function | Description |
|----------|-------------|
| `open(path, key_decoder, value_decoder)` | Open or create a table |
| `open_with(path, repair, key_decoder, value_decoder)` | Open with repair policy |
| `open_with_access(path, repair, access, key_decoder, value_decoder)` | Open with repair and access mode |
| `close(table)` | Close and flush to disk |
| `sync(table)` | Flush without closing |
| `with_table(path, key_decoder, value_decoder, fn)` | Auto-closing callback for short-lived operations |
| `insert(table, key, value)` | Insert a key-value pair |
| `insert_list(table, entries)` | Batch insert |
| `insert_new(table, key, value)` | Insert if key absent (set only) |
| `lookup(table, key)` | Get value(s) for key |
| `member(table, key)` | Check if key exists |
| `delete_key(table, key)` | Remove by key |
| `delete_object(table, key, value)` | Remove a specific key-value pair |
| `delete_all(table)` | Clear all entries |
| `to_list(table)` | Get all entries |
| `fold(table, acc, fn)` | Fold over entries |
| `size(table)` | Count entries |
| `info(table)` | Get table metadata |
| `update_counter(table, key, amount)` | Atomic counter increment (set only) |

The `slate` module also provides:

| Function | Description |
|----------|-------------|
| `is_dets_file(path)` | Check if a file is a valid DETS file |

## Limitations

- **2 GB maximum file size** per table — a hard limit in DETS
- **No `ordered_set`** — DETS only supports `set`, `bag`, and `duplicate_bag`
- **Disk I/O** on every operation — for high-frequency reads, load into ETS at startup
- **Must close properly** — `with_table` closes on callback return and attempts cleanup on callback failure, otherwise ensure `close` is called
- **Bounded table name pool** — slate uses an internal bounded set of DETS table names to avoid unbounded atom growth. Opening too many distinct tables at once can fail; close tables when no longer needed
- **Erlang only** — DETS is a BEAM feature, no JavaScript target support

## Related projects

- **[bravo](https://github.com/Michael-Mark-Edu/bravo)** — Comprehensive ETS (in-memory) bindings for Gleam
- **[shelf](https://github.com/tylerbutler/shelf)** — Persistent ETS tables backed by DETS, combining fast in-memory reads with durable storage

For details on the underlying storage engine, see the [Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).

## Development

See [DEV.md](DEV.md) for setup instructions, build tasks, and contribution guidelines.

## License

MIT
