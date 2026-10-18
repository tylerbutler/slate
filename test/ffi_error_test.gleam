import file_error_test_helper
import gleam/dynamic/decode
import gleam/option.{None}
import slate
import slate/set
import test_helper

@external(erlang, "corruption_test_helpers_ffi", "write_garbage")
fn write_garbage(path: String) -> Result(Nil, Nil)

@external(erlang, "corruption_test_ffi", "corrupt_byte")
fn corrupt_byte(path: String, position: Int) -> Result(Nil, Nil)

pub fn error_code_and_message_helpers_test() -> Nil {
  let context = slate.FileErrorContext(path: None, reason: "diagnostic")
  let assert True = slate.error_code(slate.NotFound) == "not_found"
  let assert True =
    slate.error_code(slate.UnexpectedError("boom")) == "unexpected_error"
  let assert True =
    slate.error_code(slate.NotADetsFile(context)) == "not_a_dets_file"
  let assert True =
    slate.error_code(slate.NeedsRepair(context)) == "needs_repair"

  let assert True =
    slate.error_message(slate.AccessDenied(context))
    == "The requested operation is not allowed with the current access mode."
  let assert True =
    slate.error_message(slate.UnexpectedError("boom"))
    == "An unexpected DETS error occurred."
  let assert True =
    slate.error_message(slate.NotADetsFile(context))
    == "The file exists but is not a valid DETS file."
  let assert True =
    slate.error_message(slate.NeedsRepair(context))
    == "The table file was not closed cleanly and needs repair. Open with AutoRepair or ForceRepair."
  Nil
}

pub fn not_a_dets_file_error_test() -> Nil {
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
  let assert True =
    result
    == Error(
      slate.NotADetsFile(file_error_test_helper.context(path, "not_a_dets_file")),
    )
  test_helper.cleanup(path)
}

pub fn needs_repair_error_test() -> Nil {
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
  let assert True =
    result
    == Error(
      slate.NeedsRepair(file_error_test_helper.context(path, "needs_repair")),
    )
  test_helper.cleanup(path)
}

pub fn set_info_closed_table_returns_table_does_not_exist_test() -> Nil {
  let path = "test_set_info_closed_table.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)

  let assert True = set.info(table) == Error(slate.TableDoesNotExist)

  test_helper.cleanup(path)
}
