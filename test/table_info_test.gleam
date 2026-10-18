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
  assert slate.TableInfo(file_size:, object_count:, file_path:) == info
  let slate.TableInfo(file_size: retained_size, ..) = info
  assert retained_size == 1024
}

pub fn set_info_before_and_after_close_test() -> Nil {
  let path = "test_set_info_before_and_after_close.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 1)

  let assert Ok(info) = set.info(table)
  assert info.object_count == 1
  assert info.file_size > 0

  let assert Ok(Nil) = set.close(table)
  assert set.info(table) == Error(slate.TableDoesNotExist)
  test_helper.cleanup(path)
}

pub fn bag_info_before_and_after_close_test() -> Nil {
  let path = "test_bag_info_before_and_after_close.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert_list(table, [#("key", 1), #("key", 2)])

  let assert Ok(info) = bag.info(table)
  assert info.object_count == 2
  assert info.file_size > 0

  let assert Ok(Nil) = bag.close(table)
  assert bag.info(table) == Error(slate.TableDoesNotExist)
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
  assert info.object_count == 2
  assert info.file_size > 0

  let assert Ok(Nil) = duplicate_bag.close(table)
  assert duplicate_bag.info(table) == Error(slate.TableDoesNotExist)
  test_helper.cleanup(path)
}
