import gleam/dynamic/decode
import slate
import slate/set
import startest/expect
import test_helpers.{cleanup}

pub fn dets_error_helpers_test() {
  slate.error_code(slate.NotFound) |> expect.to_equal("not_found")
  slate.error_code(slate.CounterValueNotInteger)
  |> expect.to_equal("counter_value_not_integer")
  slate.error_code(slate.UnexpectedError("boom"))
  |> expect.to_equal("unexpected_error")

  slate.error_message(slate.AccessDenied)
  |> expect.to_equal(
    "The requested operation is not allowed with the current access mode.",
  )
  slate.error_message(slate.UnexpectedError("boom"))
  |> expect.to_equal("Unexpected Erlang/OTP error: boom")
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
