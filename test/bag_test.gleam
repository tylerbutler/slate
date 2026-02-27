import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import slate
import slate/bag

// ── Bag: Open / Close ───────────────────────────────────────────────────

pub fn bag_open_close_test() {
  let path = "test_bag_open_close.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Insert / Lookup ────────────────────────────────────────────────

pub fn bag_insert_lookup_test() {
  let path = "test_bag_insert.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "color", "red")
  let assert Ok(Nil) = bag.insert(table, "color", "blue")
  let assert Ok(values) = bag.lookup(table, key: "color")
  values |> list.sort(string.compare) |> should.equal(["blue", "red"])
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_no_duplicates_test() {
  let path = "test_bag_no_dupes.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "key", "val")
  let assert Ok(Nil) = bag.insert(table, "key", "val")
  let assert Ok(values) = bag.lookup(table, key: "key")
  values |> list.length |> should.equal(1)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_lookup_empty_test() {
  let path = "test_bag_lookup_empty.dets"
  let assert Ok(table) = bag.open(path)
  bag.lookup(table, key: "missing") |> should.equal(Ok([]))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Member ─────────────────────────────────────────────────────────

pub fn bag_member_test() {
  let path = "test_bag_member.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "exists", "val")
  bag.member(table, key: "exists") |> should.equal(Ok(True))
  bag.member(table, key: "nope") |> should.equal(Ok(False))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Delete ─────────────────────────────────────────────────────────

pub fn bag_delete_key_test() {
  let path = "test_bag_delete.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "key", "a")
  let assert Ok(Nil) = bag.insert(table, "key", "b")
  let assert Ok(Nil) = bag.delete_key(table, key: "key")
  bag.lookup(table, key: "key") |> should.equal(Ok([]))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_delete_all_test() {
  let path = "test_bag_delete_all.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "b", 2)
  let assert Ok(Nil) = bag.delete_all(table)
  bag.size(table) |> should.equal(Ok(0))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Size ───────────────────────────────────────────────────────────

pub fn bag_size_test() {
  let path = "test_bag_size.dets"
  let assert Ok(table) = bag.open(path)
  bag.size(table) |> should.equal(Ok(0))
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "a", 2)
  let assert Ok(Nil) = bag.insert(table, "b", 3)
  bag.size(table) |> should.equal(Ok(3))
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Fold ───────────────────────────────────────────────────────────

pub fn bag_fold_test() {
  let path = "test_bag_fold.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "a", 10)
  let assert Ok(Nil) = bag.insert(table, "a", 20)
  let assert Ok(Nil) = bag.insert(table, "b", 30)
  let assert Ok(sum) = bag.fold(table, 0, fn(acc, _key, val) { acc + val })
  sum |> should.equal(60)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Persistence ────────────────────────────────────────────────────

pub fn bag_persistence_test() {
  let path = "test_bag_persist.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "key", "v1")
  let assert Ok(Nil) = bag.insert(table, "key", "v2")
  let assert Ok(Nil) = bag.close(table)
  // Reopen
  let assert Ok(table2) = bag.open(path)
  let assert Ok(values) = bag.lookup(table2, key: "key")
  values |> list.length |> should.equal(2)
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

// ── Bag: Info ───────────────────────────────────────────────────────────

pub fn bag_info_test() {
  let path = "test_bag_info.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(info) = bag.info(table)
  info.object_count |> should.equal(1)
  info.kind |> should.equal(slate.Bag)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Helpers ─────────────────────────────────────────────────────────────

fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, DynError)

type DynError

fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

// ── Bag: Complex value types ────────────────────────────────────────────

pub fn bag_tuple_values_test() {
  let path = "test_bag_tuple_vals.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "point", #(1, 2))
  let assert Ok(Nil) = bag.insert(table, "point", #(3, 4))
  let assert Ok(values) = bag.lookup(table, key: "point")
  values |> list.length |> should.equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_list_values_test() {
  let path = "test_bag_list_vals.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "nums", [1, 2, 3])
  let assert Ok(Nil) = bag.insert(table, "nums", [4, 5, 6])
  let assert Ok(values) = bag.lookup(table, key: "nums")
  values |> list.length |> should.equal(2)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Large dataset ──────────────────────────────────────────────────

pub fn bag_large_dataset_test() {
  let path = "test_bag_large.dets"
  let assert Ok(table) = bag.open(path)
  // Insert 100 keys with 10 values each = 1000 entries
  range(0, 99)
  |> list.each(fn(key) {
    range(0, 9)
    |> list.each(fn(val) {
      let assert Ok(Nil) = bag.insert(table, int.to_string(key), key * 10 + val)
      Nil
    })
  })
  bag.size(table) |> should.equal(Ok(1000))
  // Each key should have 10 values
  let assert Ok(vals) = bag.lookup(table, key: "0")
  vals |> list.length |> should.equal(10)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

// ── Bag: Shared access ──────────────────────────────────────────────────

pub fn bag_shared_access_test() {
  let path = "test_bag_shared.dets"
  let assert Ok(t1) = bag.open(path)
  let assert Ok(t2) = bag.open(path)
  let assert Ok(Nil) = bag.insert(t1, "key", "from_t1")
  let assert Ok(Nil) = bag.insert(t2, "key", "from_t2")
  let assert Ok(vals) = bag.lookup(t1, key: "key")
  vals |> list.length |> should.equal(2)
  let assert Ok(Nil) = bag.close(t1)
  let assert Ok(Nil) = bag.close(t2)
  cleanup(path)
}

// ── Bag: Edge cases ─────────────────────────────────────────────────────

pub fn bag_delete_nonexistent_key_test() {
  let path = "test_bag_del_missing.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.delete_key(table, key: "nope")
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_fold_empty_test() {
  let path = "test_bag_fold_empty.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(result) = bag.fold(table, 0, fn(acc, _k, _v) { acc + 1 })
  result |> should.equal(0)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_insert_list_test() {
  let path = "test_bag_insert_list.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) =
    bag.insert_list(table, [#("k", "a"), #("k", "b"), #("k", "c")])
  let assert Ok(vals) = bag.lookup(table, key: "k")
  vals |> list.sort(string.compare) |> should.equal(["a", "b", "c"])
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_with_table_test() {
  let path = "test_bag_with_table.dets"
  let assert Ok(Nil) =
    bag.with_table(path, fn(table) { bag.insert(table, "key", "val") })
  let assert Ok(table) = bag.open(path)
  let assert Ok(["val"]) = bag.lookup(table, key: "key")
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn bag_repair_policies_test() {
  let path = "test_bag_repair.dets"
  let assert Ok(table) = bag.open(path)
  let assert Ok(Nil) = bag.insert(table, "key", "val")
  let assert Ok(Nil) = bag.close(table)
  // Reopen with ForceRepair
  let assert Ok(table2) = bag.open_with(path, slate.ForceRepair)
  let assert Ok(["val"]) = bag.lookup(table2, key: "key")
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

pub fn bag_many_values_per_key_test() {
  let path = "test_bag_many_vals.dets"
  let assert Ok(table) = bag.open(path)
  let entries =
    range(0, 99)
    |> list.map(fn(i) { #("single_key", i) })
  let assert Ok(Nil) = bag.insert_list(table, entries)
  let assert Ok(vals) = bag.lookup(table, key: "single_key")
  vals |> list.length |> should.equal(100)
  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}
