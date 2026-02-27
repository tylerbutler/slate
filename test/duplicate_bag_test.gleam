import gleam/list
import gleeunit/should
import slate
import slate/duplicate_bag

// ── DuplicateBag: Open / Close ──────────────────────────────────────────

pub fn duplicate_bag_open_close_test() {
  let path = "test_dupbag_open_close.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Insert / Lookup ───────────────────────────────────────

pub fn duplicate_bag_allows_duplicates_test() {
  let path = "test_dupbag_dupes.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "val")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "key")
  values |> list.length |> should.equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_multiple_values_test() {
  let path = "test_dupbag_multi.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "b")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "c")
  let assert Ok(values) = duplicate_bag.lookup(table, key: "key")
  values |> list.length |> should.equal(3)
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_lookup_empty_test() {
  let path = "test_dupbag_empty.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  duplicate_bag.lookup(table, key: "missing") |> should.equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Size ──────────────────────────────────────────────────

pub fn duplicate_bag_size_test() {
  let path = "test_dupbag_size.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 2)
  duplicate_bag.size(table) |> should.equal(Ok(3))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Delete ────────────────────────────────────────────────

pub fn duplicate_bag_delete_key_test() {
  let path = "test_dupbag_delete.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "a")
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", "b")
  let assert Ok(Nil) = duplicate_bag.delete_key(table, key: "key")
  duplicate_bag.lookup(table, key: "key") |> should.equal(Ok([]))
  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

// ── DuplicateBag: Persistence ───────────────────────────────────────────

pub fn duplicate_bag_persistence_test() {
  let path = "test_dupbag_persist.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v1")
  let assert Ok(Nil) = duplicate_bag.insert(table, "k", "v1")
  let assert Ok(Nil) = duplicate_bag.close(table)
  // Reopen
  let assert Ok(table2) = duplicate_bag.open(path)
  let assert Ok(values) = duplicate_bag.lookup(table2, key: "k")
  values |> list.length |> should.equal(2)
  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

// ── DuplicateBag: Info ──────────────────────────────────────────────────

pub fn duplicate_bag_info_test() {
  let path = "test_dupbag_info.dets"
  let assert Ok(table) = duplicate_bag.open(path)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(info) = duplicate_bag.info(table)
  info.object_count |> should.equal(1)
  info.kind |> should.equal(slate.DuplicateBag)
  let assert Ok(Nil) = duplicate_bag.close(table)
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
