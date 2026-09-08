//// Tests for error handling edge cases.
//// Adapted from OTP dets_SUITE badarg, repair, and access tests.

import file_error_test_helper
import gleam/dynamic/decode
import gleam/int
import gleam/list
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helper

fn expect_type_mismatch_open(
  result: Result(a, slate.DetsError),
  path: String,
) -> Nil {
  result
  |> expect.to_equal(
    Error(
      slate.TypeMismatch(file_error_test_helper.context(path, "type_mismatch")),
    ),
  )
}

// ── Type mismatch: open set file as bag ─────────────────────────────────
// OTP: {error,{type_mismatch,Fname}}

pub fn type_mismatch_set_as_bag_test() -> Nil {
  let path = "test_type_mismatch_sb.dets"
  // Create as set
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // Try to open as bag — should fail
  let result =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  expect_type_mismatch_open(result, path)
  test_helper.cleanup(path)
}

pub fn type_mismatch_set_as_duplicate_bag_test() -> Nil {
  let path = "test_type_mismatch_sd.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  let result =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  expect_type_mismatch_open(result, path)
  test_helper.cleanup(path)
}

pub fn type_mismatch_bag_as_set_test() -> Nil {
  let path = "test_type_mismatch_bs.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "key", "val")
  let assert Ok(Nil) = bag.close(table)
  let result =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  expect_type_mismatch_open(result, path)
  test_helper.cleanup(path)
}

pub fn type_mismatch_bag_as_duplicate_bag_test() -> Nil {
  let path = "test_type_mismatch_bd.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "key", "val")
  let assert Ok(Nil) = bag.close(table)
  let result =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  expect_type_mismatch_open(result, path)
  test_helper.cleanup(path)
}

pub fn type_mismatch_duplicate_bag_as_set_test() -> Nil {
  let path = "test_type_mismatch_ds.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let result =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  expect_type_mismatch_open(result, path)
  test_helper.cleanup(path)
}

pub fn type_mismatch_duplicate_bag_as_bag_test() -> Nil {
  let path = "test_type_mismatch_db.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let result =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  expect_type_mismatch_open(result, path)
  test_helper.cleanup(path)
}

pub fn already_open_with_conflicting_access_test() -> Nil {
  let path = "test_already_open_access.dets"
  let assert Ok(table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  result
  |> expect.to_equal(
    Error(
      slate.AlreadyOpen(file_error_test_helper.context(
        path,
        "incompatible_arguments",
      )),
    ),
  )
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── insert_new on bag tables (OTP insert_new test) ──────────────────────
// OTP: insert_new on bag returns false if key already exists,
// even if the value is different.
// Slate bags don't expose insert_new (by design), but we can verify
// the deduplication behavior that makes insert_new less useful for bags.

pub fn bag_insert_same_key_different_values_test() -> Nil {
  let path = "test_bag_insert_diff.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "first")
  let assert Ok(Nil) = bag.insert(table, "k", "second")
  let assert Ok(values) = bag.lookup(table, key: "k")
  // Both distinct values should be present
  values |> list.length |> expect.to_equal(2)
  list.contains(values, "first") |> expect.to_be_true()
  list.contains(values, "second") |> expect.to_be_true()
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Very large key count triggering rehash (OTP-4906) ───────────────────
// OTP tests with 256*512 + 400 = 131472 keys.
// We use 5000 keys as a meaningful stress test without being too slow.

pub fn set_large_key_count_stress_test() -> Nil {
  let path = "test_set_stress.dets"
  let entry_count = 5000
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let entries =
    test_helper.range(0, entry_count - 1)
    |> list.map(fn(key) { #(key, key * 3) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  set.size(table) |> expect.to_equal(Ok(entry_count))
  // Verify first, middle, last
  let assert Ok(0) = set.lookup(table, key: 0)
  let assert Ok(7500) = set.lookup(table, key: 2500)
  let assert Ok(14_997) = set.lookup(table, key: 4999)
  // Delete half
  test_helper.range(0, 2499)
  |> list.each(fn(key) {
    let assert Ok(Nil) = set.delete_key(table, key:)
    Nil
  })
  set.size(table) |> expect.to_equal(Ok(2500))
  // Remaining keys still accessible
  let assert Ok(7500) = set.lookup(table, key: 2500)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn set_large_key_count_persistence_test() -> Nil {
  let path = "test_set_stress_persist.dets"
  let entry_count = 3000
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let entries =
    test_helper.range(0, entry_count - 1) |> list.map(fn(key) { #(key, key) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  let assert Ok(Nil) = set.close(table)
  // Reopen and verify all entries survived
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  set.size(table2) |> expect.to_equal(Ok(entry_count))
  let assert Ok(0) = set.lookup(table2, key: 0)
  let assert Ok(1500) = set.lookup(table2, key: 1500)
  let assert Ok(2999) = set.lookup(table2, key: 2999)
  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

// ── Fold with large dataset ─────────────────────────────────────────────

pub fn set_fold_large_dataset_test() -> Nil {
  let path = "test_set_fold_large.dets"
  let entry_count = 2000
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let entries =
    test_helper.range(1, entry_count)
    |> list.map(fn(value) { #(int.to_string(value), value) })
  let assert Ok(Nil) = set.insert_list(table, entries)
  let assert Ok(sum) = set.fold(table, 0, fn(acc, _key, value) { acc + value })
  // Sum of 1..2000 = 2000 * 2001 / 2 = 2_001_000
  sum |> expect.to_equal(2_001_000)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Bag fold large ──────────────────────────────────────────────────────

pub fn bag_fold_large_dataset_test() -> Nil {
  let path = "test_bag_fold_large.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  // 200 keys × 5 values each = 1000 entries
  test_helper.range(0, 199)
  |> list.each(fn(key) {
    test_helper.range(0, 4)
    |> list.each(fn(value) {
      let assert Ok(Nil) = bag.insert(table, key, value)
      Nil
    })
  })
  bag.size(table) |> expect.to_equal(Ok(1000))
  let assert Ok(count) = bag.fold(table, 0, fn(acc, _key, _value) { acc + 1 })
  count |> expect.to_equal(1000)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── delete_object on set with wrong value (OTP del_obj_test) ────────────

pub fn set_delete_object_preserves_on_mismatch_test() -> Nil {
  let path = "test_set_del_obj_mismatch.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "x", 42)
  // Try to delete with wrong value
  let assert Ok(Nil) = set.delete_object(table, "x", 99)
  // Should still be there
  let assert Ok(42) = set.lookup(table, key: "x")
  set.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── insert_list with empty list ─────────────────────────────────────────

pub fn bag_insert_list_empty_test() -> Nil {
  let path = "test_bag_ins_list_empty.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert_list(table, [])
  bag.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_insert_list_empty_test() -> Nil {
  let path = "test_dupbag_ins_list_empty.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert_list(table, [])
  duplicate_bag.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── to_list on bags ─────────────────────────────────────────────────────

pub fn bag_to_list_test() -> Nil {
  let path = "test_bag_to_list_full.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "a", 2)
  let assert Ok(Nil) = bag.insert(table, "b", 3)
  let assert Ok(entries) = bag.to_list(table)
  entries |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag to_list empty ───────────────────────────────────────────────────

pub fn bag_to_list_empty_test() -> Nil {
  let path = "test_bag_to_list_empty.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  bag.to_list(table) |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── DuplicateBag to_list empty ──────────────────────────────────────────

pub fn duplicate_bag_to_list_empty_test() -> Nil {
  let path = "test_dupbag_to_list_empty.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  duplicate_bag.to_list(table) |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Multiple insert_list calls accumulate in bags ───────────────────────

pub fn bag_multiple_insert_list_test() -> Nil {
  let path = "test_bag_multi_ins_list.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert_list(table, [#("k", 1), #("k", 2)])
  let assert Ok(Nil) = bag.insert_list(table, [#("k", 3), #("k", 4)])
  let assert Ok(values) = bag.lookup(table, key: "k")
  values |> list.length |> expect.to_equal(4)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_multiple_insert_list_test() -> Nil {
  let path = "test_dupbag_multi_ins_list.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert_list(table, [#("k", 1), #("k", 1)])
  let assert Ok(Nil) = duplicate_bag.insert_list(table, [#("k", 1), #("k", 2)])
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  // All 4 entries stored (duplicate_bag keeps everything)
  values |> list.length |> expect.to_equal(4)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

// ── Concurrent shared access (OTP many_clients adapted) ─────────────────
// DETS supports multiple openers of the same table from the same node.
// All share the same underlying table.

pub fn set_shared_write_read_test() -> Nil {
  let path = "test_set_shared_wr.dets"
  let assert Ok(first_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(second_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(third_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  // Write from each handle
  let assert Ok(Nil) = set.insert(first_table, "key1", "from_t1")
  let assert Ok(Nil) = set.insert(second_table, "key2", "from_t2")
  let assert Ok(Nil) = set.insert(third_table, "key3", "from_t3")
  // All handles see all writes
  let assert Ok("from_t1") = set.lookup(second_table, key: "key1")
  let assert Ok("from_t2") = set.lookup(third_table, key: "key2")
  let assert Ok("from_t3") = set.lookup(first_table, key: "key3")
  set.size(first_table) |> expect.to_equal(Ok(3))
  // Close all (DETS ref-counts; last close does actual close)
  let assert Ok(Nil) = set.close(first_table)
  let assert Ok(Nil) = set.close(second_table)
  let assert Ok(Nil) = set.close(third_table)
  test_helper.cleanup(path)
}

pub fn set_shared_overwrite_test() -> Nil {
  let path = "test_set_shared_ow.dets"
  let assert Ok(first_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(second_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(first_table, "key", "v1")
  let assert Ok(Nil) = set.insert(second_table, "key", "v2")
  // Last write wins
  let assert Ok("v2") = set.lookup(first_table, key: "key")
  set.size(first_table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = set.close(first_table)
  let assert Ok(Nil) = set.close(second_table)
  test_helper.cleanup(path)
}

pub fn set_shared_delete_visible_test() -> Nil {
  let path = "test_set_shared_del.dets"
  let assert Ok(first_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(second_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(first_table, "key", "val")
  let assert Ok(Nil) = set.delete_key(second_table, key: "key")
  // Delete from the second handle is visible to the first
  set.lookup(first_table, key: "key") |> expect.to_equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(first_table)
  let assert Ok(Nil) = set.close(second_table)
  test_helper.cleanup(path)
}

pub fn bag_shared_accumulate_test() -> Nil {
  let path = "test_bag_shared_acc.dets"
  let assert Ok(first_table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(second_table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(first_table, "k", "a")
  let assert Ok(Nil) = bag.insert(second_table, "k", "b")
  let assert Ok(Nil) = bag.insert(first_table, "k", "c")
  // All 3 distinct values visible from either handle
  let assert Ok(values) = bag.lookup(second_table, key: "k")
  values |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = bag.close(first_table)
  let assert Ok(Nil) = bag.close(second_table)
  test_helper.cleanup(path)
}

// ── Repair: ForceRepair rewrites healthy file ───────────────────────────
// OTP: force repair on a clean file should work and preserve data.

pub fn set_force_repair_preserves_data_test() -> Nil {
  let path = "test_set_force_repair_data.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  let assert Ok(Nil) = set.close(table)
  // Force repair
  let assert Ok(table2) =
    set.open_with(
      path:,
      repair: slate.ForceRepair,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(1) = set.lookup(table2, key: "a")
  let assert Ok(2) = set.lookup(table2, key: "b")
  let assert Ok(3) = set.lookup(table2, key: "c")
  set.size(table2) |> expect.to_equal(Ok(3))
  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

pub fn bag_force_repair_preserves_data_test() -> Nil {
  let path = "test_bag_force_repair_data.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(table2) =
    bag.open_with(
      path:,
      repair: slate.ForceRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = bag.lookup(table2, key: "k")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = bag.close(table2)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_force_repair_preserves_data_test() -> Nil {
  let path = "test_dupbag_force_repair_data.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open_with(
      path:,
      repair: slate.ForceRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "k")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}
