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
