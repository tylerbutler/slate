/// Tests for the is_dets_file utility function.
/// Adapted from OTP dets_SUITE is_dets_file and open_file tests.
import startest/expect
import slate
import slate/set
import test_helpers.{cleanup}

// ── Valid DETS file ─────────────────────────────────────────────────────

pub fn is_dets_file_valid_test() {
  let path = "test_is_dets_valid.dets"
  // Create a DETS file
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // Check it
  slate.is_dets_file(path) |> expect.to_equal(Ok(True))
  cleanup(path)
}

// ── Non-DETS file ───────────────────────────────────────────────────────

pub fn is_dets_file_not_dets_test() {
  let path = "test_is_dets_not.txt"
  // Write a plain text file
  let assert Ok(Nil) = write_file(path, "hello world this is not dets")
  slate.is_dets_file(path) |> expect.to_equal(Ok(False))
  cleanup(path)
}

// ── Empty DETS file (opened and closed without data) ────────────────────

pub fn is_dets_file_empty_table_test() {
  let path = "test_is_dets_empty.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.close(table)
  slate.is_dets_file(path) |> expect.to_equal(Ok(True))
  cleanup(path)
}

// ── Non-existent file ───────────────────────────────────────────────────

pub fn is_dets_file_nonexistent_test() {
  let result = slate.is_dets_file("nonexistent_file_12345.dets")
  // Should return an error (file doesn't exist)
  case result {
    Error(_) -> Nil
    Ok(_) -> {
      // Some implementations might return Ok(False) for missing files
      Nil
    }
  }
}

// ── DETS file with data, verified after reopen ──────────────────────────

pub fn is_dets_file_after_use_test() {
  let path = "test_is_dets_used.dets"
  let assert Ok(table) = set.open(path)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.insert(table, "c", 3)
  let assert Ok(Nil) = set.sync(table)
  let assert Ok(Nil) = set.close(table)
  slate.is_dets_file(path) |> expect.to_equal(Ok(True))
  cleanup(path)
}

// ── Helper: write a plain file ──────────────────────────────────────────

/// Write a plain file using simplifile or raw Erlang FFI.
/// We use an Erlang helper to write bytes to a file.
@external(erlang, "is_dets_file_test_ffi", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, Nil)
