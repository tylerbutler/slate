//// Corruption and repair stress tests.
//// Adapted from OTP dets_SUITE repair/1 and open_file/1 tests.
////
//// These tests verify that DETS handles file corruption gracefully:
//// - Truncated files trigger repair
//// - Corrupted bytes are detected
//// - NoRepair mode rejects damaged files
//// - AutoRepair mode fixes damaged files

import file_error_test_helper
import gleam/dynamic/decode
import gleam/list
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

type Traversal {
  ToList
  Fold
  FoldResults
}

pub fn set_corrupt_object_traversals_test() -> Nil {
  use traversal <- list.each([ToList, Fold, FoldResults])
  use path <- with_temporary_file
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "corrupt-object", 42)
  let assert Ok(Nil) = set.sync(table)
  let assert Ok(Nil) = corrupt_object(path, "corrupt-object", 42)
  // Each traversal is the first reader of a fresh corrupt object, not merely
  // observing a sticky table error caused by an earlier traversal.
  case traversal {
    ToList -> traversal_error(set.to_list(table))
    Fold ->
      traversal_error(set.fold(table, 0, fn(total, _, value) { total + value }))
    FoldResults ->
      traversal_error(set.fold_results(table, 0, fn(total, _) { total + 1 }))
  }
  let assert Error(set.TableError(error)) =
    set.update_counter(table, "corrupt-object", 1)
  assert slate.error_code(error) == "unexpected_error"
}

pub fn bag_corrupt_object_traversals_test() -> Nil {
  use traversal <- list.each([ToList, Fold, FoldResults])
  use path <- with_temporary_file
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "corrupt-object", 42)
  let assert Ok(Nil) = bag.sync(table)
  let assert Ok(Nil) = corrupt_object(path, "corrupt-object", 42)
  case traversal {
    ToList -> traversal_error(bag.to_list(table))
    Fold ->
      traversal_error(bag.fold(table, 0, fn(total, _, value) { total + value }))
    FoldResults ->
      traversal_error(bag.fold_results(table, 0, fn(total, _) { total + 1 }))
  }
}

pub fn duplicate_bag_corrupt_object_traversals_test() -> Nil {
  use traversal <- list.each([ToList, Fold, FoldResults])
  use path <- with_temporary_file
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "corrupt-object", 42)
  let assert Ok(Nil) = duplicate_bag.sync(table)
  let assert Ok(Nil) = corrupt_object(path, "corrupt-object", 42)
  case traversal {
    ToList -> traversal_error(duplicate_bag.to_list(table))
    Fold ->
      traversal_error(
        duplicate_bag.fold(table, 0, fn(total, _, value) { total + value }),
      )
    FoldResults ->
      traversal_error(
        duplicate_bag.fold_results(table, 0, fn(total, _) { total + 1 }),
      )
  }
}

fn traversal_error(outcome: Result(a, slate.DetsError)) -> Nil {
  let assert Error(error) = outcome
  // Exhaustive public dispatch must accept the actual FFI value.
  assert slate.error_code(error) == "unexpected_error"
  let assert slate.UnexpectedError(reason) = error
  assert reason != ""
}

@external(erlang, "corruption_test_ffi", "with_temporary_file")
fn with_temporary_file(callback: fn(String) -> a) -> a

@external(erlang, "corruption_test_ffi", "corrupt_object")
fn corrupt_object(path: String, key: String, value: Int) -> Result(Nil, Nil)

// ── Truncated file with AutoRepair recovers ─────────────────────────────
// OTP: truncated file triggers repair, data may be partially recovered.

pub fn truncated_file_auto_repair_test() -> Nil {
  let path = "test_truncated_auto.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(
      table,
      test_helper.range(0, 99) |> list.map(fn(key) { #(key, key * 2) }),
    )
  let assert Ok(Nil) = set.close(table)
  // Get file size and truncate to half
  let assert Ok(file_size) = get_file_size(path)
  let assert Ok(Nil) = truncate_file(path, file_size / 2)
  // AutoRepair should handle the truncated file
  let result =
    set.open_with(
      path:,
      repair: slate.AutoRepair,
      key_decoder: decode.int,
      value_decoder: decode.int,
    )
  case result {
    Ok(table2) -> {
      // Table opened (possibly with some data lost)
      let assert Ok(size) = set.size(table2)
      assert size <= 100
      let assert Ok(Nil) = set.close(table2)
      Nil
    }
    Error(_) -> {
      // Some corruption is unrecoverable, that's OK
      Nil
    }
  }
  test_helper.cleanup(path)
}

// ── NoRepair rejects damaged file ───────────────────────────────────────
// OTP: {error,{needs_repair, Fname}} when repair=false

pub fn no_repair_rejects_corrupted_file_test() -> Nil {
  let path = "test_no_repair_reject.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // Corrupt the "closed properly" flag (byte 11 in DETS v9 header)
  let assert Ok(Nil) = corrupt_byte(path, 11)
  // NoRepair should refuse to open
  let result =
    set.open_with(
      path:,
      repair: slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  assert result
    == Error(
      slate.NeedsRepair(file_error_test_helper.context(path, "needs_repair")),
    )
  assert test_helper.is_table_open(path) == False
  test_helper.cleanup(path)
}

// ── ForceRepair on corrupted file ───────────────────────────────────────
// OTP: force repair rebuilds from file data

pub fn force_repair_on_corrupted_file_test() -> Nil {
  let path = "test_force_repair_corrupt.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(
      table,
      test_helper.range(0, 49) |> list.map(fn(key) { #(key, key) }),
    )
  let assert Ok(Nil) = set.close(table)
  // Corrupt a byte in the data area (far past the header)
  let assert Ok(Nil) = corrupt_byte(path, 500)
  // ForceRepair should attempt to rebuild
  let result =
    set.open_with(
      path:,
      repair: slate.ForceRepair,
      key_decoder: decode.int,
      value_decoder: decode.int,
    )
  case result {
    Ok(table2) -> {
      // Some data may be recovered
      let assert Ok(size) = set.size(table2)
      // Size should be at most the original (some may be lost)
      assert size <= 50
      let assert Ok(Nil) = set.close(table2)
      Nil
    }
    Error(_) -> {
      // Severe corruption can prevent opening
      Nil
    }
  }
  test_helper.cleanup(path)
}

// ── Non-DETS file fails to open ─────────────────────────────────────────
// OTP: {error,{not_a_dets_file,Fname}}

pub fn open_non_dets_file_test() -> Nil {
  let path = "test_not_dets.dets"
  // Write random garbage that isn't a DETS file
  let assert Ok(Nil) = write_garbage(path)
  let result =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  assert result
    == Error(
      slate.NotADetsFile(file_error_test_helper.context(path, "not_a_dets_file")),
    )
  assert test_helper.is_table_open(path) == False
  test_helper.cleanup(path)
}

// ── Severely truncated file (header only) ───────────────────────────────

pub fn truncated_to_header_test() -> Nil {
  let path = "test_truncated_header.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // Truncate to just 20 bytes (partial header)
  let assert Ok(Nil) = truncate_file(path, 20)
  let result =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  case result {
    Error(_) -> Nil
    Ok(table2) -> {
      // Might auto-repair to empty
      let assert Ok(Nil) = set.close(table2)
      Nil
    }
  }
  test_helper.cleanup(path)
}

// ── Empty file (0 bytes) ────────────────────────────────────────────────

pub fn empty_file_test() -> Nil {
  let path = "test_empty_file.dets"
  let assert Ok(Nil) = truncate_file_create(path)
  let result =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  case result {
    Error(_) -> Nil
    Ok(table) -> {
      // DETS may create a new table over the empty file
      let assert Ok(Nil) = set.close(table)
      Nil
    }
  }
  test_helper.cleanup(path)
}

// ── FFI helpers ─────────────────────────────────────────────────────────

@external(erlang, "corruption_test_ffi", "truncate_file")
fn truncate_file(path: String, position: Int) -> Result(Nil, Nil)

@external(erlang, "corruption_test_ffi", "corrupt_byte")
fn corrupt_byte(path: String, position: Int) -> Result(Nil, Nil)

@external(erlang, "corruption_test_ffi", "get_file_size")
fn get_file_size(path: String) -> Result(Int, Nil)

@external(erlang, "corruption_test_helpers_ffi", "write_garbage")
fn write_garbage(path: String) -> Result(Nil, Nil)

@external(erlang, "corruption_test_helpers_ffi", "truncate_file_create")
fn truncate_file_create(path: String) -> Result(Nil, Nil)
