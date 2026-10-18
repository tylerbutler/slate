import file_error_test_helper
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/string
import slate
import slate/bag
import test_helper

// ── Bag: Open / Close ───────────────────────────────────────────────────

pub fn bag_open_close_test() -> Nil {
  let path = "test_bag_open_close.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Insert / Lookup ────────────────────────────────────────────────

pub fn bag_insert_lookup_test() -> Nil {
  let path = "test_bag_insert.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(values) = bag.lookup(table, key: "color")
  let assert True = { values |> list.sort(string.compare) } == ["blue", "red"]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_no_duplicates_test() -> Nil {
  let path = "test_bag_no_dupes.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert_new(table, "key", "val")
  let assert True =
    bag.insert_new(table, "key", "val") == Error(slate.KeyAlreadyPresent)
  let assert Ok(values) = bag.lookup(table, key: "key")
  let assert True = { values |> list.length } == 1
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_lookup_empty_test() -> Nil {
  let path = "test_bag_lookup_empty.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert True = bag.lookup(table, key: "missing") == Ok([])
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Member ─────────────────────────────────────────────────────────

pub fn bag_member_test() -> Nil {
  let path = "test_bag_member.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "exists", "val")
  let assert True = bag.member(table, key: "exists") == Ok(True)
  let assert True = bag.member(table, key: "nope") == Ok(False)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Delete ─────────────────────────────────────────────────────────

pub fn bag_delete_key_test() -> Nil {
  let path = "test_bag_delete.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "key", "a")
  let assert Ok(Nil) = bag.insert(table, "key", "b")
  let assert Ok(Nil) = bag.delete_key(table, key: "key")
  let assert True = bag.lookup(table, key: "key") == Ok([])
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_delete_all_test() -> Nil {
  let path = "test_bag_delete_all.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "b", 2)
  let assert Ok(Nil) = bag.delete_all(table)
  let assert True = bag.size(table) == Ok(0)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Size ───────────────────────────────────────────────────────────

pub fn bag_size_test() -> Nil {
  let path = "test_bag_size.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert True = bag.size(table) == Ok(0)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "a", 2)
  let assert Ok(Nil) = bag.insert(table, "b", 3)
  let assert True = bag.size(table) == Ok(3)
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Fold ───────────────────────────────────────────────────────────

pub fn bag_fold_test() -> Nil {
  let path = "test_bag_fold.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 10)
  let assert Ok(Nil) = bag.insert(table, "a", 20)
  let assert Ok(Nil) = bag.insert(table, "b", 30)
  let assert Ok(sum) = bag.fold(table, 0, fn(acc, _key, value) { acc + value })
  let assert True = sum == 60
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Persistence ────────────────────────────────────────────────────

pub fn bag_persistence_test() -> Nil {
  let path = "test_bag_persist.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "key", "v1")
  let assert Ok(Nil) = bag.insert(table, "key", "v2")
  let assert Ok(Nil) = bag.close(table)
  // Reopen
  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(values) = bag.lookup(table2, key: "key")
  let assert True = { values |> list.length } == 2
  let assert Ok(Nil) = bag.close(table2)
  test_helper.cleanup(path)
}

// ── Bag: Info ───────────────────────────────────────────────────────────

pub fn bag_info_test() -> Nil {
  let path = "test_bag_info.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(info) = bag.info(table)
  let assert True = info.object_count == 1
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Complex value types ────────────────────────────────────────────

pub fn bag_tuple_values_test() -> Nil {
  let path = "test_bag_tuple_vals.dets"
  let assert Ok(table) =
    bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: test_helper.unsafe_decoder(),
    )
  let assert Ok(Nil) = bag.insert(table, "point", #(1, 2))
  let assert Ok(Nil) = bag.insert(table, "point", #(3, 4))
  let assert Ok(values) = bag.lookup(table, key: "point")
  let assert True = { values |> list.length } == 2
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_list_values_test() -> Nil {
  let path = "test_bag_list_vals.dets"
  let assert Ok(table) =
    bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.list(decode.int),
    )
  let assert Ok(Nil) = bag.insert(table, "nums", [1, 2, 3])
  let assert Ok(Nil) = bag.insert(table, "nums", [4, 5, 6])
  let assert Ok(values) = bag.lookup(table, key: "nums")
  let assert True = { values |> list.length } == 2
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Large dataset ──────────────────────────────────────────────────

pub fn bag_large_dataset_test() -> Nil {
  let path = "test_bag_large.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  // Insert 100 keys with 10 values each = 1000 entries
  test_helper.range(0, 99)
  |> list.each(fn(key) {
    test_helper.range(0, 9)
    |> list.each(fn(value_index) {
      let assert Ok(Nil) =
        bag.insert(table, int.to_string(key), key * 10 + value_index)
      Nil
    })
  })
  let assert True = bag.size(table) == Ok(1000)
  // Each key should have 10 values
  let assert Ok(values) = bag.lookup(table, key: "0")
  let assert True = { values |> list.length } == 10
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

// ── Bag: Shared access ──────────────────────────────────────────────────

pub fn bag_shared_access_test() -> Nil {
  let path = "test_bag_shared.dets"
  let assert Ok(first_table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(second_table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(first_table, "key", "from_t1")
  let assert Ok(Nil) = bag.insert(second_table, "key", "from_t2")
  let assert Ok(values) = bag.lookup(first_table, key: "key")
  let assert True = { values |> list.length } == 2
  let assert Ok(Nil) = bag.close(first_table)
  let assert Ok(Nil) = bag.close(second_table)
  test_helper.cleanup(path)
}

// ── Bag: Edge cases ─────────────────────────────────────────────────────

pub fn bag_delete_nonexistent_key_test() -> Nil {
  let path = "test_bag_del_missing.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.delete_key(table, key: "nope")
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_fold_empty_test() -> Nil {
  let path = "test_bag_fold_empty.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(result) = bag.fold(table, 0, fn(acc, _key, _value) { acc + 1 })
  let assert True = result == 0
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_insert_list_test() -> Nil {
  let path = "test_bag_insert_list.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) =
    bag.insert_list(table, [#("k", "a"), #("k", "b"), #("k", "c")])
  let assert Ok(values) = bag.lookup(table, key: "k")
  let assert True = { values |> list.sort(string.compare) } == ["a", "b", "c"]
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_with_table_test() -> Nil {
  let path = "test_bag_with_table.dets"
  let assert Ok(Nil) = {
    use table <- bag.with_table(
      path,
      repair: slate.AutoRepair,
      access: slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
    bag.insert(table, "key", "val")
  }
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(["val"]) = bag.lookup(table, key: "key")
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_with_table_close_error_propagates_test() -> Nil {
  let path = "test_bag_with_close_err.dets"
  let result =
    bag.with_table(
      path,
      repair: slate.AutoRepair,
      access: slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
      callback: fn(table) {
        let assert Ok(Nil) = bag.close(table)
        Ok(Nil)
      },
    )
  let close_error_propagated = case result {
    Error(_) -> True
    Ok(_) -> False
  }
  let assert True = close_error_propagated
  test_helper.cleanup(path)
}

pub fn bag_with_table_panic_still_closes_test() -> Nil {
  let path = "test_bag_with_panic.dets"
  let assert True =
    test_helper.did_panic(fn() {
      let _ =
        bag.with_table(
          path,
          repair: slate.AutoRepair,
          access: slate.ReadWrite,
          key_decoder: decode.string,
          value_decoder: decode.string,
          callback: fn(table) {
            let assert Ok(Nil) = bag.insert(table, "key", "val")
            panic as "boom"
          },
        )
      Nil
    })
  let assert True = test_helper.is_table_open(path) == False
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(["val"]) = bag.lookup(table, key: "key")
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn bag_with_table_open_error_test() -> Nil {
  let path = "missing_bag_with_table_dir/test_bag_with_table_open_error.dets"
  let assert True =
    bag.with_table(
      path,
      repair: slate.AutoRepair,
      access: slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.string,
      callback: fn(_table) { Ok(Nil) },
    )
    == Error(slate.FileNotFound(file_error_test_helper.context(path, "enoent")))
  let assert True = test_helper.is_table_open(path) == False
  Nil
}

pub fn bag_repair_policies_test() -> Nil {
  let path = "test_bag_repair.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = bag.insert(table, "key", "val")
  let assert Ok(Nil) = bag.close(table)
  // Reopen with ForceRepair
  let assert Ok(table2) =
    bag.open_with(
      path:,
      repair: slate.ForceRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let assert Ok(["val"]) = bag.lookup(table2, key: "key")
  let assert Ok(Nil) = bag.close(table2)
  test_helper.cleanup(path)
}

pub fn bag_many_values_per_key_test() -> Nil {
  let path = "test_bag_many_vals.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let entries =
    test_helper.range(0, 99)
    |> list.map(fn(value) { #("single_key", value) })
  let assert Ok(Nil) = bag.insert_list(table, entries)
  let assert Ok(values) = bag.lookup(table, key: "single_key")
  let assert True = { values |> list.length } == 100
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}
