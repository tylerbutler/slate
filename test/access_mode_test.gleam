//// Tests for read-only access mode.
//// Adapted from OTP dets_SUITE access/1 test.

import file_error_test_helper
import gleam/dynamic/decode
import gleam/list
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

fn expect_access_denied(
  result: Result(a, slate.DetsError),
  path: String,
) -> Nil {
  let assert True =
    result
    == Error(
      slate.AccessDenied(file_error_test_helper.context(path, "access_mode")),
    )
  Nil
}

// OTP/platform versions can reject delete_all at the access check or at the
// file driver. Assert only these known reasons, not an arbitrary error.
fn expect_delete_all_denied(
  result: Result(a, slate.DetsError),
  path: String,
) -> Nil {
  let assert Error(slate.AccessDenied(context)) = result
  let assert True =
    context.path == file_error_test_helper.context(path, "access_mode").path
  let assert True =
    list.contains(
      ["access_mode", "{error,einval}", "{error,eacces}"],
      context.reason,
    )
  Nil
}

// ── Set: read-only prevents writes ──────────────────────────────────────

pub fn set_readonly_lookup_test() -> Nil {
  let path = "test_set_ro_lookup.dets"
  // First create and populate
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "value")
  let assert Ok(Nil) = set.close(table)
  // Reopen as read-only
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  // Reads should work
  let assert Ok("value") = set.lookup(read_only_table, key: "key")
  let assert True = set.member(read_only_table, key: "key") == Ok(True)
  let assert True = set.size(read_only_table) == Ok(1)
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_insert_fails_test() -> Nil {
  let path = "test_set_ro_insert.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = set.insert(read_only_table, "new_key", "val")
  expect_access_denied(result, path)
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_delete_fails_test() -> Nil {
  let path = "test_set_ro_delete.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = set.delete_key(read_only_table, key: "key")
  expect_access_denied(result, path)
  // Key should still exist
  let assert Ok("val") = set.lookup(read_only_table, key: "key")
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_delete_all_fails_test() -> Nil {
  let path = "test_set_ro_del_all.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  expect_delete_all_denied(set.delete_all(read_only_table), path)
  let _ = set.close(read_only_table)
  let assert Ok(read_write_table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok("val") = set.lookup(read_write_table, key: "key")
  let assert Ok(Nil) = set.close(read_write_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_insert_new_fails_test() -> Nil {
  let path = "test_set_ro_insert_new.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = set.insert_new(read_only_table, "key", "val")
  expect_access_denied(result, path)
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_fold_works_test() -> Nil {
  let path = "test_set_ro_fold.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(sum) =
    set.fold(read_only_table, 0, fn(acc, _key, value) { acc + value })
  let assert True = sum == 3
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_to_list_works_test() -> Nil {
  let path = "test_set_ro_to_list.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(entries) = set.to_list(read_only_table)
  let assert True = entries == [#("a", 1)]
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_info_works_test() -> Nil {
  let path = "test_set_ro_info.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(read_only_table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(info) = set.info(read_only_table)
  let assert True = info.object_count == 1
  let assert Ok(Nil) = set.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn set_readonly_nonexistent_file_fails_test() -> Nil {
  let path = "test_set_ro_nofile.dets"
  // Opening a non-existent file as read-only should fail
  let result =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert True =
    result
    == Error(slate.FileNotFound(file_error_test_helper.context(path, "enoent")))
  let assert True = test_helper.is_table_open(path) == False
  Nil
}

// ── Bag: read-only ──────────────────────────────────────────────────────

pub fn bag_readonly_lookup_test() -> Nil {
  let path = "test_bag_ro_lookup.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(read_only_table) =
    bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = bag.lookup(read_only_table, key: "k")
  let assert True =
    {
      values
      |> list.sort(string.compare)
    }
    == ["a", "b"]
  let assert Ok(Nil) = bag.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn bag_readonly_insert_fails_test() -> Nil {
  let path = "test_bag_ro_insert.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(read_only_table) =
    bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = bag.insert(read_only_table, "k", "v")
  expect_access_denied(result, path)
  let assert Ok(Nil) = bag.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn bag_readonly_delete_fails_test() -> Nil {
  let path = "test_bag_ro_delete.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "v")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(read_only_table) =
    bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = bag.delete_key(read_only_table, key: "k")
  expect_access_denied(result, path)
  let assert Ok(Nil) = bag.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn bag_readonly_delete_all_fails_test() -> Nil {
  let path = "test_bag_ro_del_all.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "v")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(read_only_table) =
    bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  expect_delete_all_denied(bag.delete_all(read_only_table), path)
  let _ = bag.close(read_only_table)
  let assert Ok(read_write_table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(["v"]) = bag.lookup(read_write_table, key: "k")
  let assert Ok(Nil) = bag.close(read_write_table)
  test_helper.cleanup(path)
}

// ── DuplicateBag: read-only ─────────────────────────────────────────────

pub fn duplicate_bag_readonly_lookup_test() -> Nil {
  let path = "test_dupbag_ro_lookup.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(read_only_table) =
    duplicate_bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(read_only_table, key: "k")
  let assert True = values == ["v", "v"]
  let assert Ok(Nil) = duplicate_bag.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_readonly_insert_fails_test() -> Nil {
  let path = "test_dupbag_ro_insert.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(read_only_table) =
    duplicate_bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = duplicate_bag.insert(read_only_table, "k", "v")
  expect_access_denied(result, path)
  let assert Ok(Nil) = duplicate_bag.close(read_only_table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_readonly_delete_all_fails_test() -> Nil {
  let path = "test_dupbag_ro_del_all.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(read_only_table) =
    duplicate_bag.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  expect_delete_all_denied(duplicate_bag.delete_all(read_only_table), path)
  let _ = duplicate_bag.close(read_only_table)
  test_helper.cleanup(path)
}

// ── ReadWrite mode works normally ───────────────────────────────────────

pub fn set_readwrite_mode_test() -> Nil {
  let path = "test_set_rw_mode.dets"
  let assert Ok(table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok("val") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}
