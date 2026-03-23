/// Tests for read-only access mode.
/// Adapted from OTP dets_SUITE access/1 test.
import gleam/dynamic/decode
import gleam/list
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helpers.{cleanup}

// ── Set: read-only prevents writes ──────────────────────────────────────

pub fn set_readonly_lookup_test() {
  let path = "test_set_ro_lookup.dets"
  // First create and populate
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "value")
  let assert Ok(Nil) = set.close(table)
  // Reopen as read-only
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  // Reads should work
  let assert Ok("value") = set.lookup(ro, key: "key")
  set.member(ro, key: "key") |> expect.to_equal(Ok(True))
  set.size(ro) |> expect.to_equal(Ok(1))
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_insert_fails_test() {
  let path = "test_set_ro_insert.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = set.insert(ro, "new_key", "val")
  result |> expect.to_equal(Error(slate.AccessDenied))
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_delete_fails_test() {
  let path = "test_set_ro_delete.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = set.delete_key(ro, key: "key")
  result |> expect.to_equal(Error(slate.AccessDenied))
  // Key should still exist
  let assert Ok("val") = set.lookup(ro, key: "key")
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_delete_all_fails_test() {
  let path = "test_set_ro_del_all.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  set.delete_all(ro) |> expect.to_equal(Error(slate.AccessDenied))
  let _ = set.close(ro)
  let assert Ok(rw) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok("val") = set.lookup(rw, key: "key")
  let assert Ok(Nil) = set.close(rw)
  cleanup(path)
}

pub fn set_readonly_insert_new_fails_test() {
  let path = "test_set_ro_insert_new.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = set.insert_new(ro, "key", "val")
  result |> expect.to_equal(Error(slate.AccessDenied))
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_fold_works_test() {
  let path = "test_set_ro_fold.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(sum) = set.fold(ro, 0, fn(acc, _k, v) { acc + v })
  sum |> expect.to_equal(3)
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_to_list_works_test() {
  let path = "test_set_ro_to_list.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(entries) = set.to_list(ro)
  entries |> expect.to_equal([#("a", 1)])
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_info_works_test() {
  let path = "test_set_ro_info.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(ro) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(info) = set.info(ro)
  info.object_count |> expect.to_equal(1)
  info.kind |> expect.to_equal(slate.Set)
  let assert Ok(Nil) = set.close(ro)
  cleanup(path)
}

pub fn set_readonly_nonexistent_file_fails_test() {
  let path = "test_set_ro_nofile.dets"
  // Opening a non-existent file as read-only should fail
  let result =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  case result {
    Error(_) -> Nil
    Ok(table) -> {
      let assert Ok(Nil) = set.close(table)
      cleanup(path)
      panic as "should have failed to open non-existent file as read-only"
    }
  }
}

// ── Bag: read-only ──────────────────────────────────────────────────────

pub fn bag_readonly_lookup_test() {
  let path = "test_bag_ro_lookup.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "a")
  let assert Ok(Nil) = bag.insert(table, "k", "b")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(ro) =
    bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = bag.lookup(ro, key: "k")
  values
  |> list.sort(string.compare)
  |> expect.to_equal(["a", "b"])
  let assert Ok(Nil) = bag.close(ro)
  cleanup(path)
}

pub fn bag_readonly_insert_fails_test() {
  let path = "test_bag_ro_insert.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(ro) =
    bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = bag.insert(ro, "k", "v")
  result |> expect.to_equal(Error(slate.AccessDenied))
  let assert Ok(Nil) = bag.close(ro)
  cleanup(path)
}

pub fn bag_readonly_delete_fails_test() {
  let path = "test_bag_ro_delete.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "v")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(ro) =
    bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = bag.delete_key(ro, key: "k")
  result |> expect.to_equal(Error(slate.AccessDenied))
  let assert Ok(Nil) = bag.close(ro)
  cleanup(path)
}

pub fn bag_readonly_delete_all_fails_test() {
  let path = "test_bag_ro_del_all.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "k", "v")
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(ro) =
    bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  bag.delete_all(ro) |> expect.to_equal(Error(slate.AccessDenied))
  let _ = bag.close(ro)
  let assert Ok(rw) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(["v"]) = bag.lookup(rw, key: "k")
  let assert Ok(Nil) = bag.close(rw)
  cleanup(path)
}

// ── DuplicateBag: read-only ─────────────────────────────────────────────

pub fn dupbag_readonly_lookup_test() {
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
  let assert Ok(ro) =
    duplicate_bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(ro, key: "k")
  values |> expect.to_equal(["v", "v"])
  let assert Ok(Nil) = duplicate_bag.close(ro)
  cleanup(path)
}

pub fn dupbag_readonly_insert_fails_test() {
  let path = "test_dupbag_ro_insert.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(ro) =
    duplicate_bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = duplicate_bag.insert(ro, "k", "v")
  result |> expect.to_equal(Error(slate.AccessDenied))
  let assert Ok(Nil) = duplicate_bag.close(ro)
  cleanup(path)
}

pub fn dupbag_readonly_delete_all_fails_test() {
  let path = "test_dupbag_ro_del_all.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(ro) =
    duplicate_bag.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  duplicate_bag.delete_all(ro) |> expect.to_equal(Error(slate.AccessDenied))
  let _ = duplicate_bag.close(ro)
  cleanup(path)
}

// ── ReadWrite mode works normally ───────────────────────────────────────

pub fn set_readwrite_mode_test() {
  let path = "test_set_rw_mode.dets"
  let assert Ok(table) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok("val") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}
