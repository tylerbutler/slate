import gleam/dynamic/decode
import gleam/int
import gleam/list
import slate
import slate/duplicate_bag
import startest/expect
import test_helpers.{cleanup, did_panic, is_table_open, range}

// ── DuplicateBag: Open / Close ──────────────────────────────────────────

pub fn duplicate_bag_open_close_test() {
  let path = "test_dupbag_open_close.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Insert / Lookup ───────────────────────────────────────

pub fn duplicate_bag_allows_duplicates_test() {
  let path = "test_dupbag_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "key")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_multiple_values_test() {
  let path = "test_dupbag_multi.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "b")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "c")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "key")
  values |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_lookup_empty_test() {
  let path = "test_dupbag_empty.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  duplicate_bag.lookup(table, key: "missing") |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Size ──────────────────────────────────────────────────

pub fn duplicate_bag_size_test() {
  let path = "test_dupbag_size.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  duplicate_bag.size(table) |> expect.to_equal(Ok(3))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Delete ────────────────────────────────────────────────

pub fn duplicate_bag_delete_key_test() {
  let path = "test_dupbag_delete.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "b")
  let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "key")
  duplicate_bag.lookup(table, key: "key") |> expect.to_equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Persistence ───────────────────────────────────────────

pub fn duplicate_bag_persistence_test() {
  let path = "test_dupbag_persist.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v1")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v1")
  let assert Ok(Nil) = duplicate_bag.close(table)
  // Reopen
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "k")
  values |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

// ── DuplicateBag: Info ──────────────────────────────────────────────────

pub fn duplicate_bag_info_test() {
  let path = "test_dupbag_info.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(info) = duplicate_bag.info(table)
  info.object_count |> expect.to_equal(1)
  info.kind |> expect.to_equal(slate.DuplicateBag)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Large duplicates ──────────────────────────────────────

pub fn duplicate_bag_many_duplicates_test() {
  let path = "test_dupbag_many_dupes.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let entries = range(0, 49) |> list.map(fn(_i) { #("key", "same_value") })
  let assert Ok(Nil) = duplicate_bag.insert_list(table, entries)
  let assert Ok(vals) = duplicate_bag.lookup(table, key: "key")
  vals |> list.length |> expect.to_equal(50)
  duplicate_bag.size(table) |> expect.to_equal(Ok(50))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Shared access ─────────────────────────────────────────

pub fn duplicate_bag_shared_access_test() {
  let path = "test_dupbag_shared.dets"
  let assert Ok(t1) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(t2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(t1, "key", "v1")
  let assert Ok(Nil) = duplicate_bag.insert(t2, "key", "v1")
  let assert Ok(vals) = duplicate_bag.lookup(t1, key: "key")
  vals |> list.length |> expect.to_equal(2)
  let assert Ok(Nil) = duplicate_bag.close(t1)
  let assert Ok(Nil) = duplicate_bag.close(t2)
  cleanup(path)
}

// ── DuplicateBag: Edge cases ────────────────────────────────────────────

pub fn duplicate_bag_delete_nonexistent_test() {
  let path = "test_dupbag_del_missing.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "nope")
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_fold_test() {
  let path = "test_dupbag_fold.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 10)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 10)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 20)
  let assert Ok(sum) = duplicate_bag.fold(table, 0, fn(acc, _k, v) { acc + v })
  sum |> expect.to_equal(40)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_to_list_test() {
  let path = "test_dupbag_to_list.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  let assert Ok(entries) = duplicate_bag.to_list(table)
  entries |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_delete_all_test() {
  let path = "test_dupbag_del_all.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  let assert Ok(Nil) = duplicate_bag.delete_all(table)
  duplicate_bag.size(table) |> expect.to_equal(Ok(0))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_with_table_test() {
  let path = "test_dupbag_with_table.dets"
  let assert Ok(Nil) =
    duplicate_bag.with_table(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
      fun: fn(table) { duplicate_bag.insert(table, "key", "val") },
    )
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(["val"]) = duplicate_bag.lookup(table, key: "key")
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_with_table_close_error_propagates_test() {
  let path = "test_dupbag_with_close_err.dets"
  let result =
    duplicate_bag.with_table(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
      fun: fn(table) {
        let assert Ok(Nil) = duplicate_bag.close(table)
        Ok(Nil)
      },
    )
  let close_error_propagated = case result {
    Error(_) -> True
    Ok(_) -> False
  }
  close_error_propagated |> expect.to_be_true()
  cleanup(path)
}

pub fn duplicate_bag_with_table_panic_still_closes_test() {
  let path = "test_dupbag_with_panic.dets"
  did_panic(fn() {
    let _ =
      duplicate_bag.with_table(
        path,
        key_decoder: decode.string,
        value_decoder: decode.string,
        fun: fn(table) {
          let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
          panic as "boom"
        },
      )
    Nil
  })
  |> expect.to_be_true()
  is_table_open(path) |> expect.to_equal(False)
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(["val"]) = duplicate_bag.lookup(table, key: "key")
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_with_table_open_error_test() {
  let path =
    "missing_dupbag_with_table_dir/test_dupbag_with_table_open_error.dets"
  duplicate_bag.with_table(
    path,
    key_decoder: decode.string,
    value_decoder: decode.string,
    fun: fn(_table) { Ok(Nil) },
  )
  |> expect.to_equal(Error(slate.FileNotFound))
  is_table_open(path) |> expect.to_equal(False)
}

pub fn duplicate_bag_repair_policies_test() {
  let path = "test_dupbag_repair.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open_with(
      path,
      slate.ForceRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(["val"]) = duplicate_bag.lookup(table2, key: "key")
  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

pub fn duplicate_bag_insert_list_test() {
  let path = "test_dupbag_insert_list.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [
      #("k", "a"),
      #("k", "a"),
      #("k", "b"),
    ])
  let assert Ok(vals) = duplicate_bag.lookup(table, key: "k")
  vals |> list.length |> expect.to_equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_large_dataset_test() {
  let path = "test_dupbag_large.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let entries =
    range(0, 999)
    |> list.map(fn(i) { #(int.to_string(i / 10), i) })
  let assert Ok(Nil) = duplicate_bag.insert_list(table, entries)
  duplicate_bag.size(table) |> expect.to_equal(Ok(1000))
  // Each of the 100 keys should have 10 values
  let assert Ok(vals) = duplicate_bag.lookup(table, key: "0")
  vals |> list.length |> expect.to_equal(10)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_member_test() {
  let path = "test_dupbag_member.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "exists", "val")
  duplicate_bag.member(table, key: "exists") |> expect.to_equal(Ok(True))
  duplicate_bag.member(table, key: "nope") |> expect.to_equal(Ok(False))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}
