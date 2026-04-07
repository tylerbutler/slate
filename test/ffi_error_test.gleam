import gleam/dynamic/decode
import slate
import slate/set
import startest/expect
import test_helpers.{cleanup}

pub fn error_code_and_message_helpers_test() {
  slate.error_code(slate.NotFound) |> expect.to_equal("not_found")
  slate.error_code(slate.NotADetsFile) |> expect.to_equal("not_a_dets_file")
  slate.error_code(slate.NeedsRepair) |> expect.to_equal("needs_repair")
  slate.error_code(slate.UnexpectedError("boom"))
  |> expect.to_equal("unexpected_error")

  slate.error_message(slate.AccessDenied)
  |> expect.to_equal(
    "The requested operation is not allowed with the current access mode.",
  )
  slate.error_message(slate.NotADetsFile)
  |> expect.to_equal("The file exists but is not a valid DETS table.")
  slate.error_message(slate.NeedsRepair)
  |> expect.to_equal(
    "The DETS file needs repair before it can be opened with this repair policy.",
  )
  slate.error_message(slate.UnexpectedError("boom"))
  |> expect.to_equal("An unexpected DETS error occurred.")
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
