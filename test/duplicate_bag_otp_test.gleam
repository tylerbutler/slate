/// Tests adapted from the Erlang/OTP dets_SUITE.erl test suite for duplicate_bag.
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import slate
import slate/duplicate_bag
import startest/expect
import test_helpers.{cleanup, range, unsafe_decoder}

// ── Duplicates are fully preserved (OTP core duplicate_bag test) ────────

pub fn dupbag_exact_duplicate_count_test() {
  let path = "test_dupbag_exact_count.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  // Insert the exact same pair 5 times
  range(1, 5)
  |> list.each(fn(_) {
    let assert Ok(Nil) = duplicate_bag.insert(table, "k", "same")
    Nil
  })
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  values |> list.length |> expect.to_equal(5)
  // All values should be identical
  values
  |> list.all(fn(v) { v == "same" })
  |> expect.to_be_true()
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── OTP-8070: insert_new with duplicate_bag ──────────────────────────────
// This is the OTP bug test. In slate, duplicate_bag doesn't expose
// insert_new, which is correct. We verify the fundamental behavior:
// duplicates are stored, not deduplicated.

pub fn dupbag_mixed_duplicates_and_distinct_test() {
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
  |> list.filter(fn(v) { v == "a" })
  |> list.length
  |> expect.to_equal(2)
  values
  |> list.filter(fn(v) { v == "b" })
  |> list.length
  |> expect.to_equal(2)
  values
  |> list.filter(fn(v) { v == "c" })
  |> list.length
  |> expect.to_equal(1)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── Integer vs Float key distinction ────────────────────────────────────

pub fn dupbag_int_key_test() {
  let path = "test_dupbag_int_key.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, 1, "int_a")
  let assert Ok(Nil) = duplicate_bag.insert(table, 1, "int_a")
  let assert Ok(vals) = duplicate_bag.lookup(table, key: 1)
  vals |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn dupbag_float_key_test() {
  let path = "test_dupbag_float_key.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.float,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, 1.0, "float_a")
  let assert Ok(Nil) = duplicate_bag.insert(table, 1.0, "float_a")
  let assert Ok(vals) = duplicate_bag.lookup(table, key: 1.0)
  vals |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── Unicode ─────────────────────────────────────────────────────────────

pub fn dupbag_unicode_test() {
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
  cleanup(path)
}

// ── Large values ────────────────────────────────────────────────────────

pub fn dupbag_large_values_test() {
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
    [v, ..] -> v
    _ -> ""
  }
  string.length(first) |> expect.to_equal(5000)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── Persistence preserves duplicate count ───────────────────────────────

pub fn dupbag_persistence_preserves_duplicates_test() {
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
  cleanup(path)
}

// ── delete_key removes all duplicates ───────────────────────────────────

pub fn dupbag_delete_key_all_duplicates_test() {
  let path = "test_dupbag_del_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let entries = range(1, 20) |> list.map(fn(_) { #("k", "same") })
  let assert Ok(Nil) = duplicate_bag.insert_list(table, entries)
  duplicate_bag.size(table) |> expect.to_equal(Ok(20))
  let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "k")
  duplicate_bag.size(table) |> expect.to_equal(Ok(0))
  duplicate_bag.lookup(table, key: "k") |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── Size counts every duplicate ─────────────────────────────────────────

pub fn dupbag_size_counts_all_duplicates_test() {
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
  cleanup(path)
}

// ── Fold counts duplicates correctly ────────────────────────────────────

pub fn dupbag_fold_counts_duplicates_test() {
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
  let assert Ok(sum) = duplicate_bag.fold(table, 0, fn(acc, _k, v) { acc + v })
  sum |> expect.to_equal(15)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── to_list includes all duplicates ─────────────────────────────────────

pub fn dupbag_to_list_includes_duplicates_test() {
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
  |> list.filter(fn(e) { e.0 == "k" && e.1 == "v" })
  |> list.length
  |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── Negative integer keys ───────────────────────────────────────────────

pub fn dupbag_negative_keys_test() {
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
  cleanup(path)
}

// ── Tuple keys ──────────────────────────────────────────────────────────

pub fn dupbag_tuple_keys_test() {
  let path = "test_dupbag_tuple_keys.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: unsafe_decoder(),
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, #("event", "click"), 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, #("event", "click"), 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, #("event", "click"), 2)
  let assert Ok(vals) = duplicate_bag.lookup(table, key: #("event", "click"))
  vals |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── Many open/close cycles ──────────────────────────────────────────────

pub fn dupbag_many_open_close_cycles_test() {
  let path = "test_dupbag_many_cycles.dets"
  range(1, 10)
  |> list.each(fn(i) {
    let assert Ok(table) =
      duplicate_bag.open(
        path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    let assert Ok(Nil) = duplicate_bag.insert(table, "round", i)
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
  cleanup(path)
}

// ── delete_all persists ─────────────────────────────────────────────────

pub fn dupbag_delete_all_persists_test() {
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
  cleanup(path)
}

// ── Large dataset with duplicates ───────────────────────────────────────

pub fn dupbag_large_with_heavy_duplicates_test() {
  let path = "test_dupbag_heavy_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  // 50 keys × 20 duplicates each = 1000 objects
  let entries =
    range(0, 49)
    |> list.flat_map(fn(key) {
      range(1, 20) |> list.map(fn(_) { #(int.to_string(key), key) })
    })
  let assert Ok(Nil) = duplicate_bag.insert_list(table, entries)
  duplicate_bag.size(table) |> expect.to_equal(Ok(1000))
  // Each key should have 20 identical values
  let assert Ok(vals) = duplicate_bag.lookup(table, key: "0")
  vals |> list.length |> expect.to_equal(20)
  vals |> list.all(fn(v) { v == 0 }) |> expect.to_be_true()
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── with_table error propagation ────────────────────────────────────────

pub fn dupbag_with_table_error_propagation_test() {
  let path = "test_dupbag_with_err.dets"
  let result =
    duplicate_bag.with_table(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
      fun: fn(_table) { Error(slate.UnexpectedError("test error")) },
    )
  result |> expect.to_equal(Error(slate.UnexpectedError("test error")))
  cleanup(path)
}

// ── Sync then reopen ────────────────────────────────────────────────────

pub fn dupbag_sync_then_reopen_test() {
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
  cleanup(path)
}

// ── Bool values ─────────────────────────────────────────────────────────

pub fn dupbag_bool_values_test() {
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
  |> list.filter(fn(v) { v == True })
  |> list.length
  |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}
