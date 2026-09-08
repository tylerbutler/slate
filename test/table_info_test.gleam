import gleam/dynamic/decode
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helpers

pub fn set_info_before_and_after_close_test() -> Nil {
  let path = "test_set_info_before_and_after_close.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 1)

  let assert Ok(info) = set.info(table)
  info.object_count |> expect.to_equal(1)
  expect.to_be_true(info.file_size > 0)

  let assert Ok(Nil) = set.close(table)
  set.info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  test_helpers.cleanup(path)
}

pub fn bag_info_before_and_after_close_test() -> Nil {
  let path = "test_bag_info_before_and_after_close.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert_list(table, [#("key", 1), #("key", 2)])

  let assert Ok(info) = bag.info(table)
  info.object_count |> expect.to_equal(2)
  expect.to_be_true(info.file_size > 0)

  let assert Ok(Nil) = bag.close(table)
  bag.info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  test_helpers.cleanup(path)
}

pub fn duplicate_bag_info_before_and_after_close_test() -> Nil {
  let path = "test_duplicate_bag_info_before_and_after_close.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [#("key", 1), #("key", 1)])

  let assert Ok(info) = duplicate_bag.info(table)
  info.object_count |> expect.to_equal(2)
  expect.to_be_true(info.file_size > 0)

  let assert Ok(Nil) = duplicate_bag.close(table)
  duplicate_bag.info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  test_helpers.cleanup(path)
}
