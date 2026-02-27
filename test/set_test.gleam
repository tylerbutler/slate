import gleam/list
import gleam/string
import gleeunit/should
import slate
import slate/set

// ── Set: Open / Close ───────────────────────────────────────────────────

pub fn set_open_close_test() {
  let path = "test_set_open_close.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_open_with_repair_test() {
  let path = "test_set_repair.dets"
  let assert Ok(table) = set.open_with(path, slate.AutoRepair)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Insert / Lookup ────────────────────────────────────────────────

pub fn set_insert_lookup_test() {
  let path = "test_set_insert.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key1", "value1")
  let assert Ok("value1") = set.lookup(table, key: "key1")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_insert_overwrites_test() {
  let path = "test_set_overwrite.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key1", "old")
  let assert Ok(Nil) = set.insert(table, "key1", "new")
  let assert Ok("new") = set.lookup(table, key: "key1")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_lookup_not_found_test() {
  let path = "test_set_not_found.dets"
  let assert Ok(table) = set.open(path)
  set.lookup(table, key: "missing")
  |> should.equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_insert_new_test() {
  let path = "test_set_insert_new.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert_new(table, "key1", "first")
  set.insert_new(table, "key1", "second")
  |> should.equal(Error(slate.KeyAlreadyPresent))
  let assert Ok("first") = set.lookup(table, key: "key1")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Member ─────────────────────────────────────────────────────────

pub fn set_member_test() {
  let path = "test_set_member.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "exists", 42)
  set.member(table, key: "exists") |> should.equal(Ok(True))
  set.member(table, key: "nope") |> should.equal(Ok(False))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Delete ─────────────────────────────────────────────────────────

pub fn set_delete_key_test() {
  let path = "test_set_delete.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key1", "val")
  let assert Ok(Nil) = set.delete_key(table, key: "key1")
  set.lookup(table, key: "key1") |> should.equal(Error(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn set_delete_all_test() {
  let path = "test_set_delete_all.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.delete_all(table)
  set.size(table) |> should.equal(Ok(0))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Size ───────────────────────────────────────────────────────────

pub fn set_size_test() {
  let path = "test_set_size.dets"
  let assert Ok(table) = set.open(path)
  set.size(table) |> should.equal(Ok(0))
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.insert(table, "c", 3)
  set.size(table) |> should.equal(Ok(3))
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: to_list ────────────────────────────────────────────────────────

pub fn set_to_list_test() {
  let path = "test_set_to_list.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(entries) = set.to_list(table)
  entries |> list.length |> should.equal(2)
  entries
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> should.equal([#("a", 1), #("b", 2)])
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Fold ───────────────────────────────────────────────────────────

pub fn set_fold_test() {
  let path = "test_set_fold.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "a", 10)
  let assert Ok(Nil) = set.insert(table, "b", 20)
  let assert Ok(Nil) = set.insert(table, "c", 30)
  let assert Ok(sum) = set.fold(table, 0, fn(acc, _key, val) { acc + val })
  sum |> should.equal(60)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Sync ───────────────────────────────────────────────────────────

pub fn set_sync_test() {
  let path = "test_set_sync.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", "value")
  let assert Ok(Nil) = set.sync(table)
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Insert list ────────────────────────────────────────────────────

pub fn set_insert_list_test() {
  let path = "test_set_insert_list.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])
  set.size(table) |> should.equal(Ok(3))
  let assert Ok(1) = set.lookup(table, key: "a")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Persistence ────────────────────────────────────────────────────

pub fn set_persistence_test() {
  let path = "test_set_persist.dets"
  // Write and close
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "persistent", "data")
  let assert Ok(Nil) = set.close(table)
  // Reopen and verify
  let assert Ok(table2) = set.open(path)
  let assert Ok("data") = set.lookup(table2, key: "persistent")
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Set: with_table ─────────────────────────────────────────────────────

pub fn set_with_table_test() {
  let path = "test_set_with_table.dets"
  let assert Ok(Nil) =
    set.with_table(path, fn(table) { set.insert(table, "key", "val") })
  // Table is closed, reopen to verify
  let assert Ok(table) = set.open(path)
  let assert Ok("val") = set.lookup(table, key: "key")
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Info ───────────────────────────────────────────────────────────

pub fn set_info_test() {
  let path = "test_set_info.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(info) = set.info(table)
  info.object_count |> should.equal(1)
  info.kind |> should.equal(slate.Set)
  { info.file_size > 0 } |> should.be_true
  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Set: Integer keys ───────────────────────────────────────────────────

pub fn set_integer_keys_test() {
  let path = "test_set_int_keys.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, 1, "one")
  let assert Ok(Nil) = set.insert(table, 2, "two")
  let assert Ok("one") = set.lookup(table, key: 1)
  let assert Ok("two") = set.lookup(table, key: 2)
  let assert Ok(Nil) = set.close(table)
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
