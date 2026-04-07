import gleam/dynamic/decode
import slate
import slate/set
import startest/expect
import test_helpers.{cleanup}

@external(erlang, "corruption_test_helpers_ffi", "write_garbage")
fn write_garbage(path: String) -> Result(Nil, Nil)

@external(erlang, "corruption_test_ffi", "corrupt_byte")
fn corrupt_byte(path: String, position: Int) -> Result(Nil, Nil)

pub fn error_code_and_message_helpers_test() {
  slate.error_code(slate.NotFound) |> expect.to_equal("not_found")
  slate.error_code(slate.UnexpectedError("boom"))
  |> expect.to_equal("unexpected_error")
  slate.error_code(slate.NotADetsFile) |> expect.to_equal("not_a_dets_file")
  slate.error_code(slate.NeedsRepair) |> expect.to_equal("needs_repair")

  slate.error_message(slate.AccessDenied)
  |> expect.to_equal(
    "The requested operation is not allowed with the current access mode.",
  )
  slate.error_message(slate.UnexpectedError("boom"))
  |> expect.to_equal("An unexpected DETS error occurred.")
  slate.error_message(slate.NotADetsFile)
  |> expect.to_equal("The file exists but is not a valid DETS file.")
  slate.error_message(slate.NeedsRepair)
  |> expect.to_equal(
    "The table file was not closed cleanly and needs repair. Open with AutoRepair or ForceRepair.",
  )
}

pub fn not_a_dets_file_error_test() {
  let path = "test_not_a_dets_error.dets"
  // Write garbage to simulate a non-DETS file
  let assert Ok(Nil) = write_garbage(path)
  let result =
    set.open_with(
      path:,
      repair: slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  case result {
    Error(slate.NotADetsFile) -> Nil
    Error(slate.UnexpectedError(_)) -> Nil
    Error(_) -> Nil
    Ok(table) -> {
      let assert Ok(Nil) = set.close(table)
      Nil
    }
  }
  cleanup(path)
}

pub fn needs_repair_error_test() {
  let path = "test_needs_repair_error.dets"
  // Create a valid table
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "key", "val")
  let assert Ok(Nil) = set.close(table)
  // Corrupt the "closed properly" flag
  let assert Ok(Nil) = corrupt_byte(path, 11)
  // NoRepair should return NeedsRepair
  let result =
    set.open_with(
      path:,
      repair: slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  case result {
    Error(slate.NeedsRepair) -> Nil
    Error(_) -> Nil
    Ok(table2) -> {
      let assert Ok(Nil) = set.close(table2)
      Nil
    }
  }
  cleanup(path)
}

pub fn set_info_closed_table_returns_table_does_not_exist_test() {
  let path = "test_set_info_closed_table.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)

  set.info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))

  cleanup(path)
}
