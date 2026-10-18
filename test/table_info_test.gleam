import gleam/dynamic/decode
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

pub fn table_info_constructor_and_pattern_test() -> Nil {
  let info =
    slate.TableInfo(
      file_size: 1024,
      object_count: 3,
      file_path: "/data/store.dets",
    )
  let slate.TableInfo(file_size, object_count, file_path) = info
  let assert True =
    slate.TableInfo(file_size:, object_count:, file_path:) == info
  let slate.TableInfo(file_size: retained_size, ..) = info
  let assert True = retained_size == 1024
  Nil
}

pub fn set_info_before_and_after_close_test() -> Nil {
  let path = "test_set_info_before_and_after_close.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 1)

  let assert Ok(info) = set.info(table)
  let assert True = info.object_count == 1
  let assert True = info.file_size > 0

  let assert Ok(Nil) = set.close(table)
  let assert True = set.info(table) == Error(slate.TableDoesNotExist)
  test_helper.cleanup(path)
}

pub fn bag_info_before_and_after_close_test() -> Nil {
  let path = "test_bag_info_before_and_after_close.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert_list(table, [#("key", 1), #("key", 2)])

  let assert Ok(info) = bag.info(table)
  let assert True = info.object_count == 2
  let assert True = info.file_size > 0

  let assert Ok(Nil) = bag.close(table)
  let assert True = bag.info(table) == Error(slate.TableDoesNotExist)
  test_helper.cleanup(path)
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
  let assert True = info.object_count == 2
  let assert True = info.file_size > 0

  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert True = duplicate_bag.info(table) == Error(slate.TableDoesNotExist)
  test_helper.cleanup(path)
}
