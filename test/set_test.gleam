import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import slate
import slate/set
import startest/expect
import test_helpers.{cleanup, range, unsafe_decoder}

// ── Set: Open / Close ───────────────────────────────────────────────────

pub fn set_open_close_test() {
  let path = "test_set_open_close.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_open_with_repair_test() {
  let path = "test_set_repair.dets"
  let assert Ok(table) =
    set.open_with(
      path,
      slate.AutoRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Insert / Lookup ────────────────────────────────────────────────

pub fn set_insert_lookup_test() {
  let path = "test_set_insert.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key1", "value1")
  let assert Ok("value1") = set.lookup(table, key: "key1")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_insert_overwrites_test() {
  let path = "test_set_overwrite.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key1", "old")
  let assert Ok(Nil) = set.insert(table, "key1", "new")
  let assert Ok("new") = set.lookup(table, key: "key1")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_lookup_not_found_test() {
  let path = "test_set_not_found.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  set.lookup(table, key: "missing")
  |> expect.to_equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_insert_new_test() {
  let path = "test_set_insert_new.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert_new(table, "key1", "first")
  set.insert_new(table, "key1", "second")
  |> expect.to_equal(Error(slate.KeyAlreadyPresent))
  let assert Ok("first") = set.lookup(table, key: "key1")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Member ─────────────────────────────────────────────────────────

pub fn set_member_test() {
  let path = "test_set_member.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "exists", 42)
  set.member(table, key: "exists") |> expect.to_equal(Ok(True))
  set.member(table, key: "nope") |> expect.to_equal(Ok(False))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Delete ─────────────────────────────────────────────────────────

pub fn set_delete_key_test() {
  let path = "test_set_delete.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key1", "val")
  let assert Ok(Nil) = set.delete_key(table, key: "key1")
  set.lookup(table, key: "key1") |> expect.to_equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_delete_all_test() {
  let path = "test_set_delete_all.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.delete_all(table)
  set.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Size ───────────────────────────────────────────────────────────

pub fn set_size_test() {
  let path = "test_set_size.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  set.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.insert(table, "c", 3)
  set.size(table) |> expect.to_equal(Ok(3))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: to_list ────────────────────────────────────────────────────────

pub fn set_to_list_test() {
  let path = "test_set_to_list.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(entries) = set.to_list(table)
  entries |> list.length |> expect.to_equal(2)
  entries
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> expect.to_equal([#("a", 1), #("b", 2)])
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Fold ───────────────────────────────────────────────────────────

pub fn set_fold_test() {
  let path = "test_set_fold.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 10)
  let assert Ok(Nil) = set.insert(table, "b", 20)
  let assert Ok(Nil) = set.insert(table, "c", 30)
  let assert Ok(sum) = set.fold(table, 0, fn(acc, _key, val) { acc + val })
  sum |> expect.to_equal(60)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Sync ───────────────────────────────────────────────────────────

pub fn set_sync_test() {
  let path = "test_set_sync.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "value")
  let assert Ok(Nil) = set.sync(table)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Insert list ────────────────────────────────────────────────────

pub fn set_insert_list_test() {
  let path = "test_set_insert_list.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  set.size(table) |> expect.to_equal(Ok(3))
  let assert Ok(1) = set.lookup(table, key: "a")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Persistence ────────────────────────────────────────────────────

pub fn set_persistence_test() {
  let path = "test_set_persist.dets"
  // Write and close
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "persistent", "data")
  let assert Ok(Nil) = set.close(table)
  // Reopen and verify
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok("data") = set.lookup(table2, key: "persistent")
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Set: with_table ─────────────────────────────────────────────────────

pub fn set_with_table_test() {
  let path = "test_set_with_table.dets"
  let assert Ok(Nil) =
    set.with_table(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
      fun: fn(table) { set.insert(table, "key", "val") },
    )
  // Table is closed, reopen to verify
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok("val") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Info ───────────────────────────────────────────────────────────

pub fn set_info_test() {
  let path = "test_set_info.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(info) = set.info(table)
  info.object_count |> expect.to_equal(1)
  info.kind |> expect.to_equal(slate.Set)
  { info.file_size > 0 } |> expect.to_be_true
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Integer keys ───────────────────────────────────────────────────

pub fn set_integer_keys_test() {
  let path = "test_set_int_keys.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, 1, "one")
  let assert Ok(Nil) = set.insert(table, 2, "two")
  let assert Ok("one") = set.lookup(table, key: 1)
  let assert Ok("two") = set.lookup(table, key: 2)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Complex value types ────────────────────────────────────────────

pub fn set_tuple_values_test() {
  let path = "test_set_tuple_vals.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: unsafe_decoder())
  let assert Ok(Nil) = set.insert(table, "point", #(10, 20))
  let assert Ok(#(10, 20)) = set.lookup(table, key: "point")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_list_values_test() {
  let path = "test_set_list_vals.dets"
  let assert Ok(table) =
    set.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.list(decode.int),
    )
  let assert Ok(Nil) = set.insert(table, "items", [1, 2, 3, 4, 5])
  let assert Ok([1, 2, 3, 4, 5]) = set.lookup(table, key: "items")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_nested_tuple_values_test() {
  let path = "test_set_nested.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: unsafe_decoder())
  let val = #("alice", #(30, "engineer"), [1, 2, 3])
  let assert Ok(Nil) = set.insert(table, "user", val)
  let assert Ok(result) = set.lookup(table, key: "user")
  result |> expect.to_equal(val)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_dict_values_test() {
  let path = "test_set_dict_vals.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: unsafe_decoder())
  let d = dict.from_list([#("a", 1), #("b", 2)])
  let assert Ok(Nil) = set.insert(table, "config", d)
  let assert Ok(result) = set.lookup(table, key: "config")
  result |> dict.get("a") |> expect.to_equal(Ok(1))
  result |> dict.get("b") |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_result_values_test() {
  let path = "test_set_result_vals.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: unsafe_decoder())
  let assert Ok(Nil) = set.insert(table, "success", Ok(42))
  let assert Ok(Nil) = set.insert(table, "failure", Error("bad"))
  let assert Ok(Ok(42)) = set.lookup(table, key: "success")
  let assert Ok(Error("bad")) = set.lookup(table, key: "failure")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Large dataset ──────────────────────────────────────────────────

pub fn set_large_dataset_test() {
  let path = "test_set_large.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  // Insert 1000 entries
  let entries =
    range(0, 999)
    |> list.map(fn(i) { #(int.to_string(i), i * i) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  // Verify size
  set.size(table) |> expect.to_equal(Ok(1000))
  // Spot-check some values
  let assert Ok(0) = set.lookup(table, key: "0")
  let assert Ok(250_000) = set.lookup(table, key: "500")
  let assert Ok(998_001) = set.lookup(table, key: "999")
  // Fold should sum all squares
  let assert Ok(sum) = set.fold(table, 0, fn(acc, _k, v) { acc + v })
  // Sum of i^2 from 0 to 999 = 999*1000*1999/6 = 332_833_500
  sum |> expect.to_equal(332_833_500)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_large_persistence_test() {
  let path = "test_set_large_persist.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)
  let entries =
    range(0, 499)
    |> list.map(fn(i) { #(i, "value_" <> int.to_string(i)) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  let assert Ok(Nil) = set.close(table)
  // Reopen and verify all entries survived
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)
  set.size(table2) |> expect.to_equal(Ok(500))
  let assert Ok("value_0") = set.lookup(table2, key: 0)
  let assert Ok("value_499") = set.lookup(table2, key: 499)
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Set: Repair policies ────────────────────────────────────────────────

pub fn set_force_repair_test() {
  let path = "test_set_force_repair.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // Reopen with ForceRepair
  let assert Ok(table2) =
    set.open_with(
      path,
      slate.ForceRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok("val") = set.lookup(table2, key: "key")
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

pub fn set_no_repair_test() {
  let path = "test_set_no_repair.dets"
  // Create and properly close a table
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // NoRepair should work on a properly closed file
  let assert Ok(table2) =
    set.open_with(
      path,
      slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok("val") = set.lookup(table2, key: "key")
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Set: Concurrent access ──────────────────────────────────────────────

pub fn set_shared_access_test() {
  let path = "test_set_shared.dets"
  // Multiple opens of the same file share the table
  let assert Ok(t1) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(t2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(t1, "from_t1", "hello")
  // t2 should see t1's write (same underlying table)
  let assert Ok("hello") = set.lookup(t2, key: "from_t1")
  let assert Ok(Nil) = set.insert(t2, "from_t2", "world")
  let assert Ok("world") = set.lookup(t1, key: "from_t2")
  // Close both (DETS ref-counts, last close does the actual close)
  let assert Ok(Nil) = set.close(t1)
  let assert Ok(Nil) = set.close(t2)
  cleanup(path)
}

pub fn set_concurrent_writers_test() {
  let path = "test_set_concurrent.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  // Simulate concurrent writes from different "logical writers"
  let assert Ok(Nil) =
    set.insert_list(
      table,
      range(0, 99) |> list.map(fn(i) { #("a_" <> int.to_string(i), i) }),
    )
  let assert Ok(Nil) =
    set.insert_list(
      table,
      range(0, 99) |> list.map(fn(i) { #("b_" <> int.to_string(i), i) }),
    )
  set.size(table) |> expect.to_equal(Ok(200))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Edge cases ─────────────────────────────────────────────────────

pub fn set_empty_string_key_test() {
  let path = "test_set_empty_key.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "", "empty_key")
  let assert Ok("empty_key") = set.lookup(table, key: "")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_empty_string_value_test() {
  let path = "test_set_empty_val.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "")
  let assert Ok("") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_delete_nonexistent_key_test() {
  let path = "test_set_del_missing.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  // Deleting a non-existent key should succeed silently
  let assert Ok(Nil) = set.delete_key(table, key: "nope")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_insert_new_after_delete_test() {
  let path = "test_set_new_after_del.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "first")
  let assert Ok(Nil) = set.delete_key(table, key: "key")
  // insert_new should work after the key is deleted
  let assert Ok(Nil) = set.insert_new(table, "key", "second")
  let assert Ok("second") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_fold_empty_table_test() {
  let path = "test_set_fold_empty.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(result) = set.fold(table, 0, fn(acc, _k, _v) { acc + 1 })
  result |> expect.to_equal(0)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_to_list_empty_test() {
  let path = "test_set_to_list_empty.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  set.to_list(table) |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_insert_list_empty_test() {
  let path = "test_set_insert_list_empty.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert_list(table, [])
  set.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_multiple_close_reopen_cycles_test() {
  let path = "test_set_cycles.dets"
  // Cycle 1: write
  let assert Ok(t) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(t, "round", 1)
  let assert Ok(Nil) = set.close(t)
  // Cycle 2: read + write more
  let assert Ok(t) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(1) = set.lookup(t, key: "round")
  let assert Ok(Nil) = set.insert(t, "round", 2)
  let assert Ok(Nil) = set.close(t)
  // Cycle 3: verify
  let assert Ok(t) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(2) = set.lookup(t, key: "round")
  let assert Ok(Nil) = set.close(t)
  cleanup(path)
}

pub fn set_with_table_error_still_closes_test() {
  let path = "test_set_with_err.dets"
  // with_table should close even when callback returns Error
  let result =
    set.with_table(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
      fun: fn(_table) { Error(slate.NotFound) },
    )
  result |> expect.to_equal(Error(slate.NotFound))
  // Table should be closed — reopening should work
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_info_grows_with_data_test() {
  let path = "test_set_info_grow.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(info1) = set.info(table)
  let initial_size = info1.file_size
  // Insert substantial data
  let entries =
    range(0, 199)
    |> list.map(fn(i) { #(int.to_string(i), string.repeat("x", 100)) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  let assert Ok(info2) = set.info(table)
  info2.object_count |> expect.to_equal(200)
  { info2.file_size > initial_size } |> expect.to_be_true
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_overwrite_preserves_size_test() {
  let path = "test_set_overwrite_size.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "v1")
  let assert Ok(Nil) = set.insert(table, "key", "v2")
  let assert Ok(Nil) = set.insert(table, "key", "v3")
  // Size should be 1 — sets overwrite, not accumulate
  set.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_fold_collects_all_keys_test() {
  let path = "test_set_fold_keys.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  let assert Ok(keys) = set.fold(table, [], fn(acc, key, _val) { [key, ..acc] })
  keys |> list.sort(string.compare) |> expect.to_equal(["a", "b", "c"])
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}
