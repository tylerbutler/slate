//// Tests for the delete_object API across all table types.
//// Adapted from OTP dets_SUITE del_obj_test and related tests.

import gleam/dynamic/decode
import gleam/list
import gleam/string
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

// ── Set: delete_object ──────────────────────────────────────────────────

pub fn set_delete_object_test() -> Nil {
  let path = "test_set_del_obj.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.delete_object(table, "key", "val")
  let assert True = set.size(table) == Ok(0)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn set_delete_object_wrong_value_test() -> Nil {
  let path = "test_set_del_obj_wrong.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "correct")
  // Deleting with wrong value should be a no-op for sets
  let assert Ok(Nil) = set.delete_object(table, "key", "wrong")
  let assert True = set.size(table) == Ok(1)
  let assert Ok("correct") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn set_delete_object_nonexistent_test() -> Nil {
  let path = "test_set_del_obj_none.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  // Deleting from empty table should succeed silently
  let assert Ok(Nil) = set.delete_object(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Bag: delete_object ──────────────────────────────────────────────────

pub fn bag_delete_object_removes_one_value_test() -> Nil {
  let path = "test_bag_del_obj.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(Nil) = bag.insert(table, "color", "green")
  // Delete only "red"
  let assert Ok(Nil) = bag.delete_object(table, "color", "red")
  let assert Ok(values) = bag.lookup(table, key: "color")
  let assert True = { values |> list.length } == 2
  let assert True = list.contains(values, "red") == False
  let assert True = list.contains(values, "blue")
  let assert True = list.contains(values, "green")
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_delete_object_all_values_one_by_one_test() -> Nil {
  let path = "test_bag_del_obj_all.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  let assert Ok(Nil) = bag.insert(table, "k", "c")
  let assert Ok(Nil) = bag.delete_object(table, "k", "a")
  let assert Ok(Nil) = bag.delete_object(table, "k", "b")
  let assert Ok(Nil) = bag.delete_object(table, "k", "c")
  let assert True = bag.size(table) == Ok(0)
  let assert True = bag.lookup(table, key: "k") == Ok([])
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_delete_object_wrong_value_test() -> Nil {
  let path = "test_bag_del_obj_wrong.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  // Delete non-existent value — should be no-op
  let assert Ok(Nil) = bag.delete_object(table, "k", "z")
  let assert True = bag.size(table) == Ok(2)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_delete_object_preserves_other_keys_test() -> Nil {
  let path = "test_bag_del_obj_other.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k1", "a")
  let assert Ok(Nil) = bag.insert(table, "k1", "b")
  let assert Ok(Nil) = bag.insert(table, "k2", "x")
  let assert Ok(Nil) = bag.delete_object(table, "k1", "a")
  // k1 should have 1 value, k2 untouched
  let assert Ok(remaining_values) = bag.lookup(table, key: "k1")
  let assert True = remaining_values == ["b"]
  let assert Ok(other_key_values) = bag.lookup(table, key: "k2")
  let assert True = other_key_values == ["x"]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_delete_object_persistence_test() -> Nil {
  let path = "test_bag_del_obj_persist.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "keep")
  let assert Ok(Nil) = bag.insert(table, "k", "remove")
  let assert Ok(Nil) = bag.delete_object(table, "k", "remove")
  let assert Ok(Nil) = bag.close(table)
  // Reopen and verify
  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(["keep"]) = bag.lookup(table2, key: "k")
  let assert Ok(Nil) = bag.close(table2)
  test_helper.cleanup(path)
}

pub fn bag_delete_object_large_test() -> Nil {
  let path = "test_bag_del_obj_large.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  // Insert 100 distinct values for one key
  test_helper.range(0, 99)
  |> list.each(fn(value) {
    let assert Ok(Nil) = bag.insert(table, "key", string.inspect(value))
    Nil
  })
  let assert True = bag.size(table) == Ok(100)
  // Delete half
  test_helper.range(0, 49)
  |> list.each(fn(value) {
    let assert Ok(Nil) = bag.delete_object(table, "key", string.inspect(value))
    Nil
  })
  let assert True = bag.size(table) == Ok(50)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── DuplicateBag: delete_object ─────────────────────────────────────────

pub fn duplicate_bag_delete_object_removes_all_copies_test() -> Nil {
  let path = "test_dupbag_del_obj.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "b")
  // delete_object removes ALL copies of {k, a}
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "a")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  let assert True = values == ["b"]
  let assert True = duplicate_bag.size(table) == Ok(1)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_delete_object_preserves_other_duplicates_test() -> Nil {
  let path = "test_dupbag_del_obj_other.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "b")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "b")
  // Delete only {k, a} copies
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "a")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k")
  let assert True = values == ["b", "b"]
  let assert True = duplicate_bag.size(table) == Ok(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_delete_object_wrong_value_test() -> Nil {
  let path = "test_dupbag_del_obj_wrong.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "a")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "z")
  let assert True = duplicate_bag.size(table) == Ok(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_delete_object_persistence_test() -> Nil {
  let path = "test_dupbag_del_obj_persist.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "keep")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "keep")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "remove")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "remove")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "k")
  let assert True = values == ["keep", "keep"]
  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_delete_object_empty_table_test() -> Nil {
  let path = "test_dupbag_del_obj_empty.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k", "v")
  let assert True = duplicate_bag.size(table) == Ok(0)
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_delete_object_preserves_other_keys_test() -> Nil {
  let path = "test_dupbag_del_obj_okeys.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k1", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k1", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k2", "b")
  let assert Ok(Nil) = duplicate_bag.delete_object(table, "k1", "a")
  let assert True = duplicate_bag.size(table) == Ok(1)
  let assert Ok(values) = duplicate_bag.lookup(table, key: "k2")
  let assert True = values == ["b"]
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}
