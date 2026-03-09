---
title: What is slate?
description: An introduction to slate and DETS.
---

:::caution[Pre-1.0 Software]
slate is not yet 1.0. The API is unstable, features may be removed in minor releases, and quality should not be considered production-ready. We welcome usage and feedback in the meantime!
:::

slate is a **type-safe Gleam wrapper** for Erlang's [DETS](https://www.erlang.org/doc/apps/stdlib/dets.html) (Disk Erlang Term Storage). It provides persistent key-value storage backed by files on disk, with a clean Gleam API.

## Why slate?

DETS is built into OTP — no external database or dependency is needed. slate fills the gap between "serialize to a file" and "add a database dependency":

| Approach | Complexity | Persistence | Query capability |
|----------|-----------|-------------|------------------|
| JSON file | Low | Yes | None |
| **DETS (slate)** | **Low** | **Yes** | **Key lookup, fold** |
| SQLite/Postgres | High | Yes | Full SQL |
| Mnesia | High | Yes | Transactions, distribution |

## Key features

- **Three table types**: `set` (unique keys), `bag` (multiple distinct values per key), `duplicate_bag` (duplicates allowed)
- **Automatic persistence**: Data survives process crashes and node restarts
- **Safe resource management**: `with_table` callbacks ensure tables are always properly closed
- **Zero external dependencies**: Built entirely on OTP's DETS module
- **Erlang target**: Runs on the BEAM virtual machine

## Related projects

- **[bravo](https://github.com/Michael-Mark-Edu/bravo)** — Comprehensive ETS (in-memory) bindings for Gleam. Use bravo when you need fast, in-memory storage without persistence.
- **[shelf](https://github.com/tylerbutler/shelf)** — Persistent ETS tables backed by DETS. Combines microsecond in-memory reads with durable disk storage. Built on top of slate.

## Learn more about DETS

slate wraps Erlang's DETS module. For details on the underlying storage engine, see the [official Erlang DETS documentation](https://www.erlang.org/doc/apps/stdlib/dets.html).
