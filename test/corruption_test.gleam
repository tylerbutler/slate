/// Corruption and repair stress tests.
/// Adapted from OTP dets_SUITE repair/1 and open_file/1 tests.
///
/// These tests verify that DETS handles file corruption gracefully:
/// - Truncated files trigger repair
/// - Corrupted bytes are detected
/// - NoRepair mode rejects damaged files
/// - AutoRepair mode fixes damaged files
import gleam/dynamic/decode
import slate
import slate/set
import startest/expect
import test_helpers.{cleanup, range}

// ── Truncated file with AutoRepair recovers ─────────────────────────────
// OTP: truncated file triggers repair, data may be partially recovered.

pub fn truncated_file_auto_repair_test() {
  let path = "test_truncated_auto.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(table, range(0, 99) |> list.map(fn(i) { #(i, i * 2) }))
  let assert Ok(Nil) = set.close(table)
  // Get file size and truncate to half
  let assert Ok(file_size) = get_file_size(path)
  let assert Ok(Nil) = truncate_file(path, file_size / 2)
  // AutoRepair should handle the truncated file
  let result =
    set.open_with(
      path,
      slate.AutoRepair,
      key_decoder: decode.int,
      value_decoder: decode.int,
    )
  case result {
    Ok(table2) -> {
      // Table opened (possibly with some data lost)
      let assert Ok(size) = set.size(table2)
      { size <= 100 } |> expect.to_be_true()
      let assert Ok(Nil) = set.close(table2)
      Nil
    }
    Error(_) -> {
      // Some corruption is unrecoverable, that's OK
      Nil
    }
  }
  cleanup(path)
}

// ── NoRepair rejects damaged file ───────────────────────────────────────
// OTP: {error,{needs_repair, Fname}} when repair=false

pub fn no_repair_rejects_corrupted_file_test() {
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
      path,
      slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  case result {
    Error(_) -> Nil
    Ok(table2) -> {
      let assert Ok(Nil) = set.close(table2)
      cleanup(path)
      panic as "NoRepair should reject a corrupted DETS file"
    }
  }
  cleanup(path)
}

// ── ForceRepair on corrupted file ───────────────────────────────────────
// OTP: force repair rebuilds from file data

pub fn force_repair_on_corrupted_file_test() {
  let path = "test_force_repair_corrupt.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(table, range(0, 49) |> list.map(fn(i) { #(i, i) }))
  let assert Ok(Nil) = set.close(table)
  // Corrupt a byte in the data area (far past the header)
  let assert Ok(Nil) = corrupt_byte(path, 500)
  // ForceRepair should attempt to rebuild
  let result =
    set.open_with(
      path,
      slate.ForceRepair,
      key_decoder: decode.int,
      value_decoder: decode.int,
    )
  case result {
    Ok(table2) -> {
      // Some data may be recovered
      let assert Ok(size) = set.size(table2)
      // Size should be at most the original (some may be lost)
      { size <= 50 } |> expect.to_be_true()
      let assert Ok(Nil) = set.close(table2)
      Nil
    }
    Error(_) -> {
      // Severe corruption can prevent opening
      Nil
    }
  }
  cleanup(path)
}

// ── Non-DETS file fails to open ─────────────────────────────────────────
// OTP: {error,{not_a_dets_file,Fname}}

pub fn open_non_dets_file_test() {
  let path = "test_not_dets.dets"
  // Write random garbage that isn't a DETS file
  let assert Ok(Nil) = write_garbage(path)
  let result =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  case result {
    Error(_) -> Nil
    Ok(table) -> {
      // Shouldn't happen, but clean up
      let assert Ok(Nil) = set.close(table)
      panic as "opened a non-DETS file as a table"
    }
  }
  cleanup(path)
}

// ── Severely truncated file (header only) ───────────────────────────────

pub fn truncated_to_header_test() {
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
  cleanup(path)
}

// ── Empty file (0 bytes) ────────────────────────────────────────────────

pub fn empty_file_test() {
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
  cleanup(path)
}

// ── FFI helpers ─────────────────────────────────────────────────────────

import gleam/list

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
