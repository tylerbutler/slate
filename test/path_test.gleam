import gleam/dynamic/decode
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect

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
  details.object_count |> expect.to_equal(0)
  expect.to_be_true(details.file_size > 0)
  string.starts_with(actual_path, "/") |> expect.to_equal(True)
  string.ends_with(actual_path, "/" <> filename) |> expect.to_equal(True)
  string.contains(actual_path, "/unused/../") |> expect.to_equal(False)

  let assert Ok(alias_table) = open(actual_path, slate.ReadWrite)
  let assert Ok(alias_info) = info(alias_table)
  alias_info.file_path |> expect.to_equal(actual_path)
  let assert Ok(Nil) = close(alias_table)
  let assert Ok(still_open_info) = info(table)
  still_open_info.file_path |> expect.to_equal(actual_path)
  let assert Ok(Nil) = close(table)
  info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))

  let assert Ok(read_only_table) = open(actual_path, slate.ReadOnly)
  let assert Ok(read_only_info) = info(read_only_table)
  read_only_info.file_path |> expect.to_equal(actual_path)
  read_only_info.object_count |> expect.to_equal(0)
  expect.to_be_true(read_only_info.file_size > 0)
  let assert Ok(Nil) = close(read_only_table)
  // Match the byte-list filename convention used by open.
  let assert Ok(Nil) = delete_file(actual_path)
  Nil
}

@external(erlang, "path_test_ffi", "delete_file")
fn delete_file(path: String) -> Result(Nil, decode.Dynamic)
