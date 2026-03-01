/// Tests for the delete_object API across all table types.
/// Adapted from OTP dets_SUITE del_obj_test and related tests.
import gleam/list
import gleam/string
import startest/expect
import slate/set
import slate/bag
import slate/duplicate_bag
import test_helpers.{cleanup, range}

// ── Set: delete_object ──────────────────────────────────────────────────

pub fn set_delete_object_test() {
  let path = "test_set_del_obj.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.delete_object(table, "key", "val")
  set.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_delete_object_wrong_value_test() {
  let path = "test_set_del_obj_wrong.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", "correct")
  // Deleting with wrong value should be a no-op for sets
  let assert Ok(Nil) = set.delete_object(table, "key", "wrong")
  set.size(table) |> expect.to_equal(Ok(1))
  let assert Ok("correct") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_delete_object_nonexistent_test() {
  let path = "test_set_del_obj_none.dets"
  let assert Ok(table) = set.open(path)
  // Deleting from empty table should succeed silently
  let assert Ok(Nil) = set.delete_object(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Bag: delete_object ──────────────────────────────────────────────────

pub fn bag_delete_object_removes_one_value_test() {
  let path = "test_bag_del_obj.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(Nil) = bag.insert(table, "color", "green")
  // Delete only "red"
  let assert Ok(Nil) = bag.delete_object(table, "color", "red")
  let assert Ok(values) = bag.lookup(table, key: "color")
  values |> list.length |> expect.to_equal(2)
  list.contains(values, "red") |> expect.to_equal(False)
  list.contains(values, "blue") |> expect.to_be_true()
  list.contains(values, "green") |> expect.to_be_true()
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_delete_object_all_values_one_by_one_test() {
  let path = "test_bag_del_obj_all.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  let assert Ok(Nil) = bag.insert(table, "k", "c")
  let assert Ok(Nil) = bag.delete_object(table, "k", "a")
  let assert Ok(Nil) = bag.delete_object(table, "k", "b")
  let assert Ok(Nil) = bag.delete_object(table, "k", "c")
  bag.size(table) |> expect.to_equal(Ok(0))
  bag.lookup(table, key: "k") |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_delete_object_wrong_value_test() {
  let path = "test_bag_del_obj_wrong.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  // Delete non-existent value — should be no-op
  let assert Ok(Nil) = bag.delete_object(table, "k", "z")
  bag.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_delete_object_preserves_other_keys_test() {
  let path = "test_bag_del_obj_other.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "k1", "a")
  let assert Ok(Nil) = bag.insert(table, "k1", "b")
  let assert Ok(Nil) = bag.insert(table, "k2", "x")
  let assert Ok(Nil) = bag.delete_object(table, "k1", "a")
  // k1 should have 1 value, k2 untouched
  let assert Ok(vals1) = bag.lookup(table, key: "k1")
  vals1 |> expect.to_equal(["b"])
  let assert Ok(vals2) = bag.lookup(table, key: "k2")
  vals2 |> expect.to_equal(["x"])
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_delete_object_persistence_test() {
  let path = "test_bag_del_obj_persist.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "k", "keep")
  let assert Ok(Nil) = bag.insert(table, "k", "remove")
  let assert Ok(Nil) = bag.delete_object(table, "k", "remove")
  let assert Ok(Nil) = bag.close(table)
  // Reopen and verify
  let assert Ok(table2) = bag.open(path)
  let assert Ok(["keep"]) = bag.lookup(table2, key: "k")
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

pub fn bag_delete_object_large_test() {
  let path = "test_bag_del_obj_large.dets"
  let assert Ok(table) = bag.open(path)
  // Insert 100 distinct values for one key
  range(0, 99)
  |> list.each(fn(i) {
    let assert Ok(Nil) = bag.insert(table, "key", string.inspect(i))
    Nil
  })
  bag.size(table) |> expect.to_equal(Ok(100))
  // Delete half
  range(0, 49)
  |> list.each(fn(i) {
    let assert Ok(Nil) = bag.delete_object(table, "key", string.inspect(i))
    Nil
  })
  bag.size(table) |> expect.to_equal(Ok(50))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: delete_object ─────────────────────────────────────────

pub fn dupbag_delete_object_removes_all_copies_test() {
  let path = "test_dupbag_del_obj.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "b")
  // delete_object removes ALL copies of {k, a}
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "a")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  values |> expect.to_equal(["b"])
  duplicate_bag.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn dupbag_delete_object_preserves_other_duplicates_test() {
  let path = "test_dupbag_del_obj_other.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "b")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "b")
  // Delete only {k, a} copies
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "a")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  values |> expect.to_equal(["b", "b"])
  duplicate_bag.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn dupbag_delete_object_wrong_value_test() {
  let path = "test_dupbag_del_obj_wrong.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "z")
  duplicate_bag.size(table) |> expect.to_equal(Ok(2))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn dupbag_delete_object_persistence_test() {
  let path = "test_dupbag_del_obj_persist.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "keep")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "keep")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "remove")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "remove")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) = duplicate_bag.open(path)
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "k")
  values |> expect.to_equal(["keep", "keep"])
  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

pub fn dupbag_delete_object_empty_table_test() {
  let path = "test_dupbag_del_obj_empty.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "v")
  duplicate_bag.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn dupbag_delete_object_preserves_other_keys_test() {
  let path = "test_dupbag_del_obj_okeys.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "k1", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k1", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k2", "b")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k1", "a")
  duplicate_bag.size(table) |> expect.to_equal(Ok(1))
  let assert Ok(vals) = duplicate_bag.lookup(table, key: "k2")
  vals |> expect.to_equal(["b"])
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}
