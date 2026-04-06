/// Tests adapted from the Erlang/OTP dets_SUITE.erl test suite for bag tables.
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import slate
import slate/bag
import startest/expect
import test_helpers.{cleanup, range, unsafe_decoder}

// ── insert_new semantics for bags (OTP insert_new test) ─────────────────
// In OTP: insert_new on a bag returns false if the *key* already exists,
// even if the value is different. Bags in slate don't expose insert_new,
// so we test that insert properly deduplicates.

pub fn bag_insert_deduplicates_test() {
  let path = "test_bag_dedup.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert_new(table, "color", "red")
  bag.insert_new(table, "color", "red")
  |> expect.to_equal(Error(slate.KeyAlreadyPresent))
  bag.insert_new(table, "color", "red")
  |> expect.to_equal(Error(slate.KeyAlreadyPresent))
  let assert Ok(values) = bag.lookup(table, key: "color")
  values |> list.length |> expect.to_equal(1)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Multiple distinct values per key ────────────────────────────────────

pub fn bag_many_distinct_values_test() {
  let path = "test_bag_distinct.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let colors = ["red", "blue", "green", "yellow", "purple", "orange"]
  colors
  |> list.each(fn(c) {
    let assert Ok(Nil) = bag.insert(table, "color", c)
    Nil
  })
  let assert Ok(values) = bag.lookup(table, key: "color")
  values |> list.length |> expect.to_equal(6)
  // All distinct colors should be present
  colors
  |> list.each(fn(c) { list.contains(values, c) |> expect.to_be_true() })
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Integer vs Float key distinction ────────────────────────────────────

pub fn bag_int_key_test() {
  let path = "test_bag_int_key.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, 1, "int_a")
  let assert Ok(Nil) = bag.insert(table, 1, "int_b")
  let assert Ok(vals) = bag.lookup(table, key: 1)
  vals |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_float_key_test() {
  let path = "test_bag_float_key.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.float, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, 1.0, "float_a")
  let assert Ok(Nil) = bag.insert(table, 1.0, "float_b")
  let assert Ok(vals) = bag.lookup(table, key: 1.0)
  vals |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Unicode keys and values ─────────────────────────────────────────────

pub fn bag_unicode_test() {
  let path = "test_bag_unicode.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "タグ", "日本語")
  let assert Ok(Nil) = bag.insert(table, "タグ", "英語")
  let assert Ok(values) = bag.lookup(table, key: "タグ")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Large values ────────────────────────────────────────────────────────

pub fn bag_large_values_test() {
  let path = "test_bag_large_vals.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let big_a = string.repeat("A", 3000)
  let big_b = string.repeat("B", 3000)
  let assert Ok(Nil) = bag.insert(table, "key", big_a)
  let assert Ok(Nil) = bag.insert(table, "key", big_b)
  let assert Ok(values) = bag.lookup(table, key: "key")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Delete key removes all values ───────────────────────────────────────

pub fn bag_delete_key_removes_all_values_test() {
  let path = "test_bag_del_all_vals.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "v1")
  let assert Ok(Nil) = bag.insert(table, "k", "v2")
  let assert Ok(Nil) = bag.insert(table, "k", "v3")
  bag.size(table) |> expect.to_equal(Ok(3))
  let assert Ok(Nil) = bag.delete_key(table, key: "k")
  bag.size(table) |> expect.to_equal(Ok(0))
  bag.lookup(table, key: "k") |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── delete_all then reuse ───────────────────────────────────────────────

pub fn bag_delete_all_reuse_test() {
  let path = "test_bag_del_all_reuse.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert_list(table, [#("a", 1), #("a", 2), #("b", 3)])
  let assert Ok(Nil) = bag.delete_all(table)
  bag.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = bag.insert(table, "x", 42)
  bag.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Persistence with multiple values ────────────────────────────────────

pub fn bag_persistence_multiple_values_test() {
  let path = "test_bag_persist_multi.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "tags", "gleam")
  let assert Ok(Nil) = bag.insert(table, "tags", "erlang")
  let assert Ok(Nil) = bag.insert(table, "tags", "beam")
  let assert Ok(Nil) = bag.close(table)
  // Reopen
  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(values) = bag.lookup(table2, key: "tags")
  values |> list.length |> expect.to_equal(3)
  list.contains(values, "gleam") |> expect.to_be_true()
  list.contains(values, "erlang") |> expect.to_be_true()
  list.contains(values, "beam") |> expect.to_be_true()
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

// ── Size counts each value separately ───────────────────────────────────

pub fn bag_size_counts_objects_not_keys_test() {
  let path = "test_bag_size_objects.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k1", "a")
  let assert Ok(Nil) = bag.insert(table, "k1", "b")
  let assert Ok(Nil) = bag.insert(table, "k1", "c")
  let assert Ok(Nil) = bag.insert(table, "k2", "x")
  // 4 objects total (3 for k1, 1 for k2)
  bag.size(table) |> expect.to_equal(Ok(4))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Fold over bag accumulates all entries ────────────────────────────────

pub fn bag_fold_all_entries_test() {
  let path = "test_bag_fold_all.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 10)
  let assert Ok(Nil) = bag.insert(table, "a", 20)
  let assert Ok(Nil) = bag.insert(table, "b", 30)
  let assert Ok(Nil) = bag.insert(table, "b", 40)
  let assert Ok(pairs) = bag.fold(table, [], fn(acc, k, v) { [#(k, v), ..acc] })
  pairs |> list.length |> expect.to_equal(4)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Boundary: negative integer keys ─────────────────────────────────────

pub fn bag_negative_keys_test() {
  let path = "test_bag_neg_keys.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, -1, "neg_one")
  let assert Ok(Nil) = bag.insert(table, -1, "neg_one_b")
  let assert Ok(values) = bag.lookup(table, key: -1)
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Tuple keys in bags ──────────────────────────────────────────────────

pub fn bag_tuple_keys_test() {
  let path = "test_bag_tuple_keys.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: unsafe_decoder(), value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, #("user", 1), "admin")
  let assert Ok(Nil) = bag.insert(table, #("user", 1), "editor")
  let assert Ok(Nil) = bag.insert(table, #("user", 2), "viewer")
  let assert Ok(vals_1) = bag.lookup(table, key: #("user", 1))
  vals_1 |> list.length |> expect.to_equal(2)
  let assert Ok(vals_2) = bag.lookup(table, key: #("user", 2))
  vals_2 |> expect.to_equal(["viewer"])
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Many open/close cycles ──────────────────────────────────────────────

pub fn bag_many_open_close_cycles_test() {
  let path = "test_bag_many_cycles.dets"
  range(1, 10)
  |> list.each(fn(i) {
    let assert Ok(table) =
      bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
    let assert Ok(Nil) = bag.insert(table, "round", i)
    let assert Ok(Nil) = bag.close(table)
    Nil
  })
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(values) = bag.lookup(table, key: "round")
  // Bag keeps distinct values, so we get 10 values
  values |> list.length |> expect.to_equal(10)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── with_table error propagation ────────────────────────────────────────

pub fn bag_with_table_error_propagation_test() {
  let path = "test_bag_with_err.dets"
  let result =
    bag.with_table(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
      fun: fn(_table) { Error(slate.UnexpectedError("test error")) },
    )
  result |> expect.to_equal(Error(slate.UnexpectedError("test error")))
  cleanup(path)
}

// ── Large dataset with many keys ────────────────────────────────────────

pub fn bag_large_many_keys_test() {
  let path = "test_bag_large_keys.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  // 500 keys, 2 values each = 1000 objects
  let entries =
    range(0, 499)
    |> list.flat_map(fn(i) {
      [#(int.to_string(i), i), #(int.to_string(i), i + 1000)]
    })
  let assert Ok(Nil) = bag.insert_list(table, entries)
  bag.size(table) |> expect.to_equal(Ok(1000))
  // Each key should have 2 values
  let assert Ok(vals) = bag.lookup(table, key: "0")
  vals |> list.length |> expect.to_equal(2)
  let assert Ok(vals_last) = bag.lookup(table, key: "499")
  vals_last |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── member on empty bag ─────────────────────────────────────────────────

pub fn bag_member_empty_test() {
  let path = "test_bag_member_empty.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  bag.member(table, key: "anything") |> expect.to_equal(Ok(False))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Sync then reopen ────────────────────────────────────────────────────

pub fn bag_sync_then_reopen_test() {
  let path = "test_bag_sync_reopen.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "key", "synced")
  let assert Ok(Nil) = bag.sync(table)
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(["synced"]) = bag.lookup(table2, key: "key")
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}
