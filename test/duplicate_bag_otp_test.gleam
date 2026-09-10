//// Tests adapted from the Erlang/OTP dets_SUITE.erl test suite for duplicate_bag.

import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import slate
import slate/duplicate_bag
import startest/expect
import test_helper

// ── Duplicates are fully preserved (OTP core duplicate_bag test) ────────

pub fn duplicate_bag_exact_duplicate_count_test() -> Nil {
  let path = "test_dupbag_exact_count.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  // Insert the exact same pair 5 times
  test_helper.range(1, 5)
  |> list.each(fn(_) {
    let assert Ok(Nil) = duplicate_bag.insert(table, "k", "same")
    Nil
  })
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  values |> list.length |> expect.to_equal(5)
  // All values should be identical
  values
  |> list.all(fn(value) { value == "same" })
  |> expect.to_be_true()
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── OTP-8070: insert_new with duplicate_bag ──────────────────────────────
// This is the OTP bug test. In slate, duplicate_bag doesn't expose
// insert_new, which is correct. We verify the fundamental behavior:
// duplicates are stored, not deduplicated.

pub fn duplicate_bag_mixed_duplicates_and_distinct_test() -> Nil {
  let path = "test_dupbag_mixed.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [
      #("k", "a"),
      #("k", "b"),
      #("k", "a"),
      #("k", "b"),
      #("k", "c"),
    ])
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  // All 5 should be stored (2×a, 2×b, 1×c)
  values |> list.length |> expect.to_equal(5)
  values
  |> list.filter(fn(value) { value == "a" })
  |> list.length
  |> expect.to_equal(2)
  values
  |> list.filter(fn(value) { value == "b" })
  |> list.length
  |> expect.to_equal(2)
  values
  |> list.filter(fn(value) { value == "c" })
  |> list.length
  |> expect.to_equal(1)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Integer vs Float key distinction ────────────────────────────────────

pub fn duplicate_bag_int_key_test() -> Nil {
  let path = "test_dupbag_int_key.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, 1, "int_a")
  let assert Ok(Nil) = duplicate_bag.insert(table, 1, "int_a")
  let assert Ok(values) = duplicate_bag.lookup(table, key: 1)
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_float_key_test() -> Nil {
  let path = "test_dupbag_float_key.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.float,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, 1.0, "float_a")
  let assert Ok(Nil) = duplicate_bag.insert(table, 1.0, "float_a")
  let assert Ok(values) = duplicate_bag.lookup(table, key: 1.0)
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Unicode ─────────────────────────────────────────────────────────────

pub fn duplicate_bag_unicode_test() -> Nil {
  let path = "test_dupbag_unicode.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "🔑", "🎉")
  let assert Ok(Nil) = duplicate_bag.insert(table, "🔑", "🎉")
  let assert Ok(Nil) = duplicate_bag.insert(table, "🔑", "🚀")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "🔑")
  values |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Large values ────────────────────────────────────────────────────────

pub fn duplicate_bag_large_values_test() -> Nil {
  let path = "test_dupbag_large_vals.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let big = string.repeat("X", 5000)
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", big)
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", big)
  let assert Ok(values) = duplicate_bag.lookup(table, key: "key")
  values |> list.length |> expect.to_equal(2)
  let first = case values {
    [value, ..] -> value
    _ -> ""
  }
  string.length(first) |> expect.to_equal(5000)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Persistence preserves duplicate count ───────────────────────────────

pub fn duplicate_bag_persistence_preserves_duplicates_test() -> Nil {
  let path = "test_dupbag_persist_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "k")
  values |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}

// ── delete_key removes all duplicates ───────────────────────────────────

pub fn duplicate_bag_delete_key_all_duplicates_test() -> Nil {
  let path = "test_dupbag_del_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let entries = test_helper.range(1, 20) |> list.map(fn(_) { #("k", "same") })
  let assert Ok(Nil) = duplicate_bag.insert_list(table, entries)
  duplicate_bag.size(table) |> expect.to_equal(Ok(20))
  let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "k")
  duplicate_bag.size(table) |> expect.to_equal(Ok(0))
  duplicate_bag.lookup(table, key: "k") |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Size counts every duplicate ─────────────────────────────────────────

pub fn duplicate_bag_size_counts_all_duplicates_test() -> Nil {
  let path = "test_dupbag_size_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 2)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 1)
  // 5 total objects: a→1, a→1, a→2, b→1, b→1
  duplicate_bag.size(table) |> expect.to_equal(Ok(5))
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Fold counts duplicates correctly ────────────────────────────────────

pub fn duplicate_bag_fold_counts_duplicates_test() -> Nil {
  let path = "test_dupbag_fold_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 5)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 5)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 5)
  let assert Ok(sum) =
    duplicate_bag.fold(table, 0, fn(acc, _key, value) { acc + value })
  sum |> expect.to_equal(15)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── to_list includes all duplicates ─────────────────────────────────────

pub fn duplicate_bag_to_list_includes_duplicates_test() -> Nil {
  let path = "test_dupbag_to_list_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "other", "w")
  let assert Ok(entries) = duplicate_bag.to_list(table)
  entries |> list.length |> expect.to_equal(3)
  entries
  |> list.filter(fn(entry) { entry.0 == "k" && entry.1 == "v" })
  |> list.length
  |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Negative integer keys ───────────────────────────────────────────────

pub fn duplicate_bag_negative_keys_test() -> Nil {
  let path = "test_dupbag_neg_keys.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, -42, "val")
  let assert Ok(Nil) = duplicate_bag.insert(table, -42, "val")
  let assert Ok(values) = duplicate_bag.lookup(table, key: -42)
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Tuple keys ──────────────────────────────────────────────────────────

pub fn duplicate_bag_tuple_keys_test() -> Nil {
  let path = "test_dupbag_tuple_keys.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: test_helper.unsafe_decoder(),
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, #("event", "click"), 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, #("event", "click"), 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, #("event", "click"), 2)
  let assert Ok(values) = duplicate_bag.lookup(table, key: #("event", "click"))
  values |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Many open/close cycles ──────────────────────────────────────────────

pub fn duplicate_bag_many_open_close_cycles_test() -> Nil {
  let path = "test_dupbag_many_cycles.dets"
  test_helper.range(1, 10)
  |> list.each(fn(round) {
    let assert Ok(table) =
      duplicate_bag.open(
        path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    let assert Ok(Nil) = duplicate_bag.insert(table, "round", round)
    let assert Ok(Nil) = duplicate_bag.close(table)
    Nil
  })
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(values) = duplicate_bag.lookup(table, key: "round")
  // Duplicate bag stores all, so 10 entries
  values |> list.length |> expect.to_equal(10)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── delete_all persists ─────────────────────────────────────────────────

pub fn duplicate_bag_delete_all_persists_test() -> Nil {
  let path = "test_dupbag_del_all_persist.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.delete_all(table)
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  duplicate_bag.size(table2) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}

// ── Large dataset with duplicates ───────────────────────────────────────

pub fn duplicate_bag_large_with_heavy_duplicates_test() -> Nil {
  let path = "test_dupbag_heavy_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  // 50 keys × 20 duplicates each = 1000 objects
  let entries =
    test_helper.range(0, 49)
    |> list.flat_map(fn(key) {
      test_helper.range(1, 20)
      |> list.map(fn(_) { #(int.to_string(key), key) })
    })
  let assert Ok(Nil) = duplicate_bag.insert_list(table, entries)
  duplicate_bag.size(table) |> expect.to_equal(Ok(1000))
  // Each key should have 20 identical values
  let assert Ok(values) = duplicate_bag.lookup(table, key: "0")
  values |> list.length |> expect.to_equal(20)
  values |> list.all(fn(value) { value == 0 }) |> expect.to_be_true()
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── with_table error propagation ────────────────────────────────────────

pub fn duplicate_bag_with_table_error_propagation_test() -> Nil {
  let path = "test_dupbag_with_err.dets"
  let result =
    duplicate_bag.with_table(
      path,
      repair: slate.AutoRepair,
      access: slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
      callback: fn(_table) { Error(slate.UnexpectedError("test error")) },
    )
  result |> expect.to_equal(Error(slate.UnexpectedError("test error")))
  test_helper.cleanup(path)
}

// ── Sync then reopen ────────────────────────────────────────────────────

pub fn duplicate_bag_sync_then_reopen_test() -> Nil {
  let path = "test_dupbag_sync_reopen.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "synced")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "synced")
  let assert Ok(Nil) = duplicate_bag.sync(table)
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "key")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}

// ── Bool values ─────────────────────────────────────────────────────────

pub fn duplicate_bag_bool_values_test() -> Nil {
  let path = "test_dupbag_bool_vals.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.bool,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "flag", True)
  let assert Ok(Nil) = duplicate_bag.insert(table, "flag", True)
  let assert Ok(Nil) = duplicate_bag.insert(table, "flag", False)
  let assert Ok(values) = duplicate_bag.lookup(table, key: "flag")
  values |> list.length |> expect.to_equal(3)
  values
  |> list.filter(fn(value) { value == True })
  |> list.length
  |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}
