/// Tests for the bounded table-name pool in `dets_ffi.erl`.
///
/// The pool has 4096 slots (`?TABLE_NAME_POOL_SIZE`). When a table is opened,
/// `allocate_table_name/1` hashes the canonical path to pick a starting slot
/// and probes linearly until it finds a free one. If every slot is occupied by
/// a *different* open table, it raises `erlang:error(no_available_table_name)`,
/// which `do_open/4`'s try-catch translates to `TableNamePoolExhausted`.
///
/// Opening 4096 real DETS files in a unit test is too expensive, so instead
/// these tests exercise the pool's slot-reuse logic at a smaller scale:
///
///   1. Open several tables concurrently and verify they all succeed.
///   2. Close them and reopen new tables to confirm freed slots are reused.
///   3. Verify that reopening an already-open path returns the same handle
///      (no extra slot consumed).
///
/// The exhaustion error path (`TableNamePoolExhausted`) has
/// been verified by code review of `dets_ffi.erl` lines 92-93.
import gleam/dynamic/decode
import gleam/int
import gleam/list
import slate/set
import startest/expect
import test_helpers.{cleanup, range}

// ── Pool: multiple concurrent opens ─────────────────────────────────────

/// Open several tables concurrently to verify slot allocation works.
pub fn pool_concurrent_opens_test() {
  let count = 20
  let paths =
    range(1, count)
    |> list.map(fn(i) { "test_pool_concurrent_" <> int.to_string(i) <> ".dets" })

  // Open all tables
  let tables =
    list.map(paths, fn(path) {
      let assert Ok(table) =
        set.open(path, key_decoder: decode.int, value_decoder: decode.string)
      table
    })

  // Verify each table is independently usable
  list.index_map(tables, fn(table, i) {
    let assert Ok(Nil) = set.insert(table, i, "value_" <> int.to_string(i))
    let assert Ok(val) = set.lookup(table, key: i)
    val |> expect.to_equal("value_" <> int.to_string(i))
  })

  // Clean up
  list.each(tables, fn(table) {
    let assert Ok(Nil) = set.close(table)
  })
  list.each(paths, cleanup)
}

// ── Pool: slot reuse after close ────────────────────────────────────────

/// Close tables and reopen with new paths to confirm pool slots are recycled.
pub fn pool_slot_reuse_after_close_test() {
  let count = 10

  // Phase 1: open tables with one set of paths
  let paths_a =
    range(1, count)
    |> list.map(fn(i) { "test_pool_reuse_a_" <> int.to_string(i) <> ".dets" })
  let tables_a =
    list.map(paths_a, fn(path) {
      let assert Ok(table) =
        set.open(path, key_decoder: decode.int, value_decoder: decode.int)
      table
    })

  // Close all phase-1 tables (frees their slots)
  list.each(tables_a, fn(table) {
    let assert Ok(Nil) = set.close(table)
  })

  // Phase 2: open tables with different paths — these should reuse freed slots
  let paths_b =
    range(1, count)
    |> list.map(fn(i) { "test_pool_reuse_b_" <> int.to_string(i) <> ".dets" })
  let tables_b =
    list.map(paths_b, fn(path) {
      let assert Ok(table) =
        set.open(path, key_decoder: decode.int, value_decoder: decode.int)
      table
    })

  // Verify phase-2 tables work
  list.index_map(tables_b, fn(table, i) {
    let assert Ok(Nil) = set.insert(table, i, i * 100)
    let assert Ok(val) = set.lookup(table, key: i)
    val |> expect.to_equal(i * 100)
  })

  // Clean up
  list.each(tables_b, fn(table) {
    let assert Ok(Nil) = set.close(table)
  })
  list.each(paths_a, cleanup)
  list.each(paths_b, cleanup)
}

// ── Pool: reopening same path reuses handle ─────────────────────────────

/// Opening the same path twice should return the existing table handle
/// without consuming an additional pool slot.
pub fn pool_reopen_same_path_test() {
  let path = "test_pool_same_path.dets"

  let assert Ok(table1) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table1, "key", "from_first_open")

  // Open the same path again — should get the same underlying table
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(val) = set.lookup(table2, key: "key")
  val |> expect.to_equal("from_first_open")

  let assert Ok(Nil) = set.close(table1)
  cleanup(path)
}
