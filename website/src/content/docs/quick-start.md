---
title: Quick Start
description: Get up and running with slate in minutes.
---

:::caution[Pre-1.0 Software]
slate is not yet 1.0. The API is unstable and features may be removed in minor releases.
:::

This guide walks you through basic DETS operations with slate.

## 1. Add slate to your project

```bash
gleam add slate
```

## 2. Open a table and store data

```gleam
import slate/set

pub fn main() {
  // Open or create a table
  let assert Ok(users) = set.open("data/users.dets")

  // Insert key-value pairs
  let assert Ok(Nil) = set.insert(users, "alice", 42)
  let assert Ok(Nil) = set.insert(users, "bob", 37)

  // Look up values
  let assert Ok(age) = set.lookup(users, key: "alice")
  // age == 42

  // Always close when done
  let assert Ok(Nil) = set.close(users)
}
```

## 3. Data persists across restarts

```gleam
import slate/set

pub fn write() {
  let assert Ok(table) = set.open("data/state.dets")
  let assert Ok(Nil) = set.insert(table, "counter", 42)
  let assert Ok(Nil) = set.close(table)
}

pub fn read() {
  let assert Ok(table) = set.open("data/state.dets")
  let assert Ok(42) = set.lookup(table, key: "counter")
  let assert Ok(Nil) = set.close(table)
}
```

## Next steps

- Learn about [Set Tables](/guides/set-tables/) for unique key-value storage
- Use [Bag Tables](/guides/bag-tables/) for multiple values per key
- Explore [Duplicate Bag Tables](/guides/duplicate-bag-tables/) for allowing duplicates
- Use [`with_table`](/advanced/with-table/) for safe resource management
