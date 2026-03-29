import gleam/dynamic/decode
import slate
import slate/set
import startest/expect
import test_helpers.{cleanup}

pub fn set_info_closed_table_returns_table_does_not_exist_test() {
  let path = "test_set_info_closed_table.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.close(table)

  set.info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))

  cleanup(path)
}
