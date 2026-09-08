import gleam/dynamic/decode
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect

pub fn set_path_test() -> Nil {
  check_path(
    "test_set_path.dets",
    fn(path) {
      set.open(path, key_decoder: decode.string, value_decoder: decode.int)
    },
    set.path,
    set.close,
  )
}

pub fn bag_path_test() -> Nil {
  check_path(
    "test_bag_path.dets",
    fn(path) {
      bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
    },
    bag.path,
    bag.close,
  )
}

pub fn duplicate_bag_path_test() -> Nil {
  check_path(
    "test_duplicate_bag_path.dets",
    fn(path) {
      duplicate_bag.open(
        path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    duplicate_bag.path,
    duplicate_bag.close,
  )
}

pub fn set_unicode_path_test() -> Nil {
  check_path(
    "test_path_\u{e9}_\u{1f4be}.dets",
    fn(path) {
      set.open(path, key_decoder: decode.string, value_decoder: decode.int)
    },
    set.path,
    set.close,
  )
}

fn check_path(
  filename: String,
  open: fn(String) -> Result(table, slate.DetsError),
  path: fn(table) -> Result(String, slate.DetsError),
  close: fn(table) -> Result(Nil, slate.DetsError),
) -> Nil {
  let assert Ok(table) = open("./unused/../" <> filename)
  let assert Ok(actual_path) = path(table)
  string.starts_with(actual_path, "/") |> expect.to_equal(True)
  string.ends_with(actual_path, "/" <> filename) |> expect.to_equal(True)
  string.contains(actual_path, "/unused/../") |> expect.to_equal(False)

  let assert Ok(alias_table) = open(actual_path)
  path(alias_table) |> expect.to_equal(Ok(actual_path))
  let assert Ok(Nil) = close(alias_table)
  path(table) |> expect.to_equal(Ok(actual_path))
  let assert Ok(Nil) = close(table)
  path(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  // Match the byte-list filename convention used by open.
  let assert Ok(Nil) = delete_file(actual_path)
  Nil
}

@external(erlang, "path_test_ffi", "delete_file")
fn delete_file(path: String) -> Result(Nil, decode.Dynamic)
