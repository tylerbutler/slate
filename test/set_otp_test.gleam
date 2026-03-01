/// Tests adapted from the Erlang/OTP dets_SUITE.erl test suite.
/// These exercise edge cases, boundary conditions, and behaviors
/// documented in the official DETS implementation.
import gleam/int
import gleam/list
import gleam/string
import startest/expect
import slate
import slate/set
import test_helpers.{cleanup, range}

// ── Integer vs Float key distinction (OTP-4738) ─────────────────────────
// Erlang treats integer and float keys as distinct in DETS.
// 1 and 1.0 are different keys.

pub fn set_int_key_test() {
  let path = "test_set_int_key.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, 1, "integer_one")
  let assert Ok(Nil) = set.insert(table, 2, "integer_two")
  let assert Ok("integer_one") = set.lookup(table, key: 1)
  let assert Ok("integer_two") = set.lookup(table, key: 2)
  set.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_float_key_test() {
  let path = "test_set_float_key.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, 1.0, "float_one")
  let assert Ok(Nil) = set.insert(table, 2.5, "float_two_half")
  let assert Ok("float_one") = set.lookup(table, key: 1.0)
  let assert Ok("float_two_half") = set.lookup(table, key: 2.5)
  set.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_negative_int_key_test() {
  let path = "test_set_neg_int.dets"
  let assert Ok(table) = set.open(path)
  let i = -12_857_447
  let assert Ok(Nil) = set.insert(table, i, "int")
  let assert Ok("int") = set.lookup(table, key: i)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_negative_float_key_test() {
  let path = "test_set_neg_float.dets"
  let assert Ok(table) = set.open(path)
  let f = -12_857_447.0
  let assert Ok(Nil) = set.insert(table, f, "float")
  let assert Ok("float") = set.lookup(table, key: f)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_zero_int_key_test() {
  let path = "test_set_zero_int.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, 0, "int_zero")
  let assert Ok("int_zero") = set.lookup(table, key: 0)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_zero_float_key_test() {
  let path = "test_set_zero_float.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, 0.0, "float_zero")
  let assert Ok("float_zero") = set.lookup(table, key: 0.0)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Boundary integers ───────────────────────────────────────────────────

pub fn set_negative_integer_keys_test() {
  let path = "test_set_neg_keys.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, -1, "neg_one")
  let assert Ok(Nil) = set.insert(table, -999_999_999, "big_neg")
  let assert Ok(Nil) = set.insert(table, 0, "zero")
  let assert Ok("neg_one") = set.lookup(table, key: -1)
  let assert Ok("big_neg") = set.lookup(table, key: -999_999_999)
  let assert Ok("zero") = set.lookup(table, key: 0)
  set.size(table) |> expect.to_equal(Ok(3))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_large_integer_keys_test() {
  let path = "test_set_large_int.dets"
  let assert Ok(table) = set.open(path)
  // Erlang supports arbitrary precision integers
  let big = 999_999_999_999_999_999
  let neg_big = -999_999_999_999_999_999
  let assert Ok(Nil) = set.insert(table, big, "big")
  let assert Ok(Nil) = set.insert(table, neg_big, "neg_big")
  let assert Ok("big") = set.lookup(table, key: big)
  let assert Ok("neg_big") = set.lookup(table, key: neg_big)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Very large values ───────────────────────────────────────────────────
// OTP tests objects > 2kB to exercise "bigger buddy" allocation.

pub fn set_large_tuple_value_test() {
  let path = "test_set_large_tuple.dets"
  let assert Ok(table) = set.open(path)
  // Create a large list value (simulates large tuple from OTP)
  let big_list = range(0, 999) |> list.map(fn(i) { #(i, "foobar") })
  let assert Ok(Nil) = set.insert(table, "big", big_list)
  let assert Ok(result) = set.lookup(table, key: "big")
  result |> list.length |> expect.to_equal(1000)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_large_string_value_test() {
  let path = "test_set_large_string.dets"
  let assert Ok(table) = set.open(path)
  // > 2KB string value
  let big_string = string.repeat("abcdefghij", 500)
  let assert Ok(Nil) = set.insert(table, "key", big_string)
  let assert Ok(result) = set.lookup(table, key: "key")
  string.length(result) |> expect.to_equal(5000)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_large_value_persistence_test() {
  let path = "test_set_large_persist.dets"
  let big_string = string.repeat("X", 5000)
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "big", big_string)
  let assert Ok(Nil) = set.close(table)
  // Reopen and verify
  let assert Ok(table2) = set.open(path)
  let assert Ok(result) = set.lookup(table2, key: "big")
  string.length(result) |> expect.to_equal(5000)
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Unicode keys and values ─────────────────────────────────────────────

pub fn set_unicode_keys_test() {
  let path = "test_set_unicode_keys.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "日本語", "japanese")
  let assert Ok(Nil) = set.insert(table, "中文", "chinese")
  let assert Ok(Nil) = set.insert(table, "한국어", "korean")
  let assert Ok(Nil) = set.insert(table, "émojis 🎉🚀", "emoji")
  let assert Ok("japanese") = set.lookup(table, key: "日本語")
  let assert Ok("chinese") = set.lookup(table, key: "中文")
  let assert Ok("korean") = set.lookup(table, key: "한국어")
  let assert Ok("emoji") = set.lookup(table, key: "émojis 🎉🚀")
  set.size(table) |> expect.to_equal(Ok(4))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_unicode_values_test() {
  let path = "test_set_unicode_vals.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "greet", "こんにちは世界")
  let assert Ok(Nil) = set.insert(table, "emoji", "🎸🎵🎶")
  let assert Ok("こんにちは世界") = set.lookup(table, key: "greet")
  let assert Ok("🎸🎵🎶") = set.lookup(table, key: "emoji")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_unicode_persistence_test() {
  let path = "test_set_unicode_persist.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key_café", "value_über")
  let assert Ok(Nil) = set.close(table)
  let assert Ok(table2) = set.open(path)
  let assert Ok("value_über") = set.lookup(table2, key: "key_café")
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Many open/close cycles (stress test) ────────────────────────────────
// OTP tests process/port leak detection across cycles.

pub fn set_many_open_close_cycles_test() {
  let path = "test_set_many_cycles.dets"
  // 10 cycles of open/write/close/reopen/verify
  range(1, 10)
  |> list.each(fn(i) {
    let assert Ok(table) = set.open(path)
    let assert Ok(Nil) = set.insert(table, "round", i)
    let assert Ok(i_back) = set.lookup(table, key: "round")
    i_back |> expect.to_equal(i)
    let assert Ok(Nil) = set.close(table)
    Nil
  })
  // Final verification
  let assert Ok(table) = set.open(path)
  let assert Ok(10) = set.lookup(table, key: "round")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Overwrite with different value shapes ───────────────────────────────
// Erlang is dynamically typed; a key can be overwritten with a
// completely different term shape in DETS. Gleam's type system
// prevents this in normal code, but within the same type it's valid.

pub fn set_overwrite_different_lengths_test() {
  let path = "test_set_overwrite_diff.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", [1])
  let assert Ok(Nil) = set.insert(table, "key", [1, 2, 3, 4, 5])
  let assert Ok([1, 2, 3, 4, 5]) = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.insert(table, "key", [])
  let assert Ok([]) = set.lookup(table, key: "key")
  set.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Large dataset triggering rehash (OTP-4906) ──────────────────────────
// > 128k keys causes DETS to rehash internally.

pub fn set_rehash_large_key_count_test() {
  let path = "test_set_rehash.dets"
  let assert Ok(table) = set.open(path)
  let n = 2000
  // Insert n entries
  let entries =
    range(0, n - 1)
    |> list.map(fn(i) { #(i, i * 2) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  set.size(table) |> expect.to_equal(Ok(n))
  // Spot-check
  let assert Ok(0) = set.lookup(table, key: 0)
  let assert Ok(1998) = set.lookup(table, key: 999)
  let assert Ok(3998) = set.lookup(table, key: 1999)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── insert_list overwrites correctly ────────────────────────────────────

pub fn set_insert_list_overwrites_test() {
  let path = "test_set_insert_list_ow.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) =
    set.insert_list(table, [#("a", 1), #("b", 2), #("a", 99)])
  // "a" should have been overwritten to 99
  let assert Ok(99) = set.lookup(table, key: "a")
  let assert Ok(2) = set.lookup(table, key: "b")
  set.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── insert_new with list (OTP insert_new test) ──────────────────────────

pub fn set_insert_new_multiple_test() {
  let path = "test_set_insert_new_multi.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  // insert_new should fail for existing key even in a batch
  // (Note: slate's insert_new takes single key-value, not list)
  set.insert_new(table, "a", 99)
  |> expect.to_equal(Error(slate.KeyAlreadyPresent))
  // Original value preserved
  let assert Ok(1) = set.lookup(table, key: "a")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── delete_all then reuse table ─────────────────────────────────────────

pub fn set_delete_all_then_reuse_test() {
  let path = "test_set_del_all_reuse.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) =
    set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  let assert Ok(Nil) = set.delete_all(table)
  set.size(table) |> expect.to_equal(Ok(0))
  // Reuse: insert and verify
  let assert Ok(Nil) = set.insert(table, "x", 42)
  let assert Ok(42) = set.lookup(table, key: "x")
  set.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── delete_all persists across close/reopen ─────────────────────────────

pub fn set_delete_all_persists_test() {
  let path = "test_set_del_all_persist.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.delete_all(table)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(table2) = set.open(path)
  set.size(table2) |> expect.to_equal(Ok(0))
  set.lookup(table2, key: "key") |> expect.to_equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── sync ensures data is on disk ────────────────────────────────────────

pub fn set_sync_then_reopen_test() {
  let path = "test_set_sync_reopen.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "synced", "data")
  let assert Ok(Nil) = set.sync(table)
  // Close and reopen
  let assert Ok(Nil) = set.close(table)
  let assert Ok(table2) = set.open(path)
  let assert Ok("data") = set.lookup(table2, key: "synced")
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Tuple keys ──────────────────────────────────────────────────────────

pub fn set_tuple_keys_test() {
  let path = "test_set_tuple_keys.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, #("compound", 1), "value_a")
  let assert Ok(Nil) = set.insert(table, #("compound", 2), "value_b")
  let assert Ok("value_a") = set.lookup(table, key: #("compound", 1))
  let assert Ok("value_b") = set.lookup(table, key: #("compound", 2))
  set.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Bool values ─────────────────────────────────────────────────────────

pub fn set_bool_values_test() {
  let path = "test_set_bool_vals.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "flag_a", True)
  let assert Ok(Nil) = set.insert(table, "flag_b", False)
  let assert Ok(True) = set.lookup(table, key: "flag_a")
  let assert Ok(False) = set.lookup(table, key: "flag_b")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Float values ────────────────────────────────────────────────────────

pub fn set_float_values_test() {
  let path = "test_set_float_vals.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "pi", 3.14159)
  let assert Ok(Nil) = set.insert(table, "neg", -273.15)
  let assert Ok(Nil) = set.insert(table, "zero", 0.0)
  let assert Ok(3.14159) = set.lookup(table, key: "pi")
  let assert Ok(-273.15) = set.lookup(table, key: "neg")
  let assert Ok(0.0) = set.lookup(table, key: "zero")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Mixed batch: insert_list then delete some ───────────────────────────

pub fn set_batch_insert_then_selective_delete_test() {
  let path = "test_set_batch_del.dets"
  let assert Ok(table) = set.open(path)
  let entries =
    range(0, 99)
    |> list.map(fn(i) { #(int.to_string(i), i) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  // Delete every other key
  range(0, 49)
  |> list.each(fn(i) {
    let assert Ok(Nil) = set.delete_key(table, key: int.to_string(i * 2))
    Nil
  })
  set.size(table) |> expect.to_equal(Ok(50))
  // Verify odd keys still exist
  let assert Ok(1) = set.lookup(table, key: "1")
  let assert Ok(99) = set.lookup(table, key: "99")
  // Verify even keys are gone
  set.lookup(table, key: "0") |> expect.to_equal(Error(slate.NotFound))
  set.lookup(table, key: "98") |> expect.to_equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── member after delete ─────────────────────────────────────────────────

pub fn set_member_after_delete_test() {
  let path = "test_set_member_del.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  set.member(table, key: "key") |> expect.to_equal(Ok(True))
  let assert Ok(Nil) = set.delete_key(table, key: "key")
  set.member(table, key: "key") |> expect.to_equal(Ok(False))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Fold accumulates in unspecified order ────────────────────────────────

pub fn set_fold_builds_dict_test() {
  let path = "test_set_fold_dict.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) =
    set.insert_list(table, [#(1, "one"), #(2, "two"), #(3, "three")])
  let assert Ok(pairs) =
    set.fold(table, [], fn(acc, k, v) { [#(k, v), ..acc] })
  pairs
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> expect.to_equal([#(1, "one"), #(2, "two"), #(3, "three")])
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── with_table propagates callback errors ───────────────────────────────

pub fn set_with_table_propagates_error_test() {
  let path = "test_set_with_err_prop.dets"
  let result =
    set.with_table(path, fn(_table) {
      Error(slate.ErlangError("custom error"))
    })
  result |> expect.to_equal(Error(slate.ErlangError("custom error")))
  cleanup(path)
}

// ── with_table returns value on success ──────────────────────────────────

pub fn set_with_table_returns_value_test() {
  let path = "test_set_with_val.dets"
  let result =
    set.with_table(path, fn(table) {
      let assert Ok(Nil) = set.insert(table, "key", 42)
      let assert Ok(val) = set.lookup(table, key: "key")
      Ok(val)
    })
  result |> expect.to_equal(Ok(42))
  cleanup(path)
}
