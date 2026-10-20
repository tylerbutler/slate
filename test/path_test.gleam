import gleam/dynamic/decode
import gleam/list
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/set

pub fn absolute_root_normalization_test() -> Nil {
  list.each(root_cases(), fn(example) {
    let #(input, expected) = example
    assert canonical_path(input) == expected
    assert canonical_path(expected) == expected
    assert is_absolute(canonical_path(input))
  })
}

pub fn set_info_path_test() -> Nil {
  check_path(
    "test_set_path.dets",
    fn(path, access) {
      set.open_with_access(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    set.info,
    set.close,
  )
}

pub fn bag_info_path_test() -> Nil {
  check_path(
    "test_bag_path.dets",
    fn(path, access) {
      bag.open_with_access(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    bag.info,
    bag.close,
  )
}

pub fn duplicate_bag_info_path_test() -> Nil {
  check_path(
    "test_duplicate_bag_path.dets",
    fn(path, access) {
      duplicate_bag.open_with_access(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    duplicate_bag.info,
    duplicate_bag.close,
  )
}

pub fn set_info_unicode_path_test() -> Nil {
  check_path(
    "test_path_\u{e9}_\u{1f4be}.dets",
    fn(path, access) {
      set.open_with_access(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    set.info,
    set.close,
  )
}

fn check_path(
  filename: String,
  open: fn(String, slate.AccessMode) -> Result(table, slate.DetsError),
  info: fn(table) -> Result(slate.TableInfo, slate.DetsError),
  close: fn(table) -> Result(Nil, slate.DetsError),
) -> Nil {
  let assert Ok(table) = open("./unused/../" <> filename, slate.ReadWrite)
  let assert Ok(details) = info(table)
  let actual_path = details.file_path
  assert details.object_count == 0
  assert details.file_size > 0
  assert is_absolute(actual_path)
  assert string.ends_with(actual_path, "/" <> filename) == True
  assert string.contains(actual_path, "/unused/../") == False

  let assert Ok(alias_table) = open(actual_path, slate.ReadWrite)
  assert same_table(table, alias_table)
  let assert Ok(alias_info) = info(alias_table)
  assert alias_info.file_path == actual_path
  let assert Ok(Nil) = close(alias_table)
  let parent_alias = above_root_alias(actual_path)
  assert canonical_path(parent_alias) == actual_path
  assert canonical_path(canonical_path(parent_alias)) == actual_path
  let assert Ok(parent_table) = open(parent_alias, slate.ReadWrite)
  assert same_table(table, parent_table)
  let assert Ok(Nil) = close(parent_table)
  let assert Ok(still_open_info) = info(table)
  assert still_open_info.file_path == actual_path
  let assert Ok(Nil) = close(table)
  assert info(table) == Error(slate.TableDoesNotExist)

  let assert Ok(read_only_table) = open(actual_path, slate.ReadOnly)
  let assert Ok(read_only_info) = info(read_only_table)
  assert read_only_info.file_path == actual_path
  assert read_only_info.object_count == 0
  assert read_only_info.file_size > 0
  let assert Ok(Nil) = close(read_only_table)
  // Match the byte-list filename convention used by open.
  let assert Ok(Nil) = delete_file(actual_path)
  Nil
}

type FileDeleteError

@external(erlang, "path_test_ffi", "delete_file")
fn delete_file(path: String) -> Result(Nil, FileDeleteError)

@external(erlang, "path_test_ffi", "is_absolute")
fn is_absolute(path: String) -> Bool

@external(erlang, "path_test_ffi", "canonical_path")
fn canonical_path(path: String) -> String

@external(erlang, "path_test_ffi", "above_root_alias")
fn above_root_alias(path: String) -> String

@external(erlang, "path_test_ffi", "root_cases")
fn root_cases() -> List(#(String, String))

@external(erlang, "path_test_ffi", "same_table")
fn same_table(first: table, second: table) -> Bool
