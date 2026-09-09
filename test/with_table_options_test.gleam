import file_error_test_helper
import gleam/dynamic/decode
import gleam/list
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helper

pub fn set_with_table_options_test() -> Nil {
  check_options(
    "test_set_scoped_options.dets",
    fn(path, repair, access, fun) {
      set.with_table(
        path:,
        repair:,
        access:,
        key_decoder: decode.string,
        value_decoder: decode.int,
        fun:,
      )
    },
    set.insert,
    set.size,
    set.close,
  )
}

pub fn bag_with_table_options_test() -> Nil {
  check_options(
    "test_bag_scoped_options.dets",
    fn(path, repair, access, fun) {
      bag.with_table(
        path:,
        repair:,
        access:,
        key_decoder: decode.string,
        value_decoder: decode.int,
        fun:,
      )
    },
    bag.insert,
    bag.size,
    bag.close,
  )
}

pub fn duplicate_bag_with_table_options_test() -> Nil {
  check_options(
    "test_duplicate_bag_scoped_options.dets",
    fn(path, repair, access, fun) {
      duplicate_bag.with_table(
        path:,
        repair:,
        access:,
        key_decoder: decode.string,
        value_decoder: decode.int,
        fun:,
      )
    },
    duplicate_bag.insert,
    duplicate_bag.size,
    duplicate_bag.close,
  )
}

fn check_options(
  path: String,
  with_table: fn(
    String,
    slate.RepairPolicy,
    slate.AccessMode,
    fn(table) -> Result(Int, slate.DetsError),
  ) -> Result(Int, slate.DetsError),
  insert: fn(table, String, Int) -> Result(Nil, slate.DetsError),
  size: fn(table) -> Result(Int, slate.DetsError),
  close: fn(table) -> Result(Nil, slate.DetsError),
) -> Nil {
  test_helper.cleanup(path)
  with_table(path, slate.NoRepair, slate.ReadWrite, fn(table) {
    let assert Ok(Nil) = insert(table, "key", 42)
    Ok(42)
  })
  |> expect.to_equal(Ok(42))
  test_helper.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(table) {
    insert(table, "other", 99)
    |> expect.to_equal(
      Error(
        slate.AccessDenied(file_error_test_helper.context(path, "access_mode")),
      ),
    )
    size(table)
  })
  |> expect.to_equal(Ok(1))
  test_helper.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(_table) {
    Error(slate.NotFound)
  })
  |> expect.to_equal(Error(slate.NotFound))
  test_helper.is_table_open(path) |> expect.to_equal(False)

  let close_error =
    with_table(path, slate.NoRepair, slate.ReadOnly, fn(table) {
      let assert Ok(Nil) = close(table)
      Ok(42)
    })
  list.contains(
    [
      Error(slate.TableDoesNotExist),
      Error(slate.UnexpectedError("not_owner")),
    ],
    close_error,
  )
  |> expect.to_equal(True)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(table) {
    let assert Ok(Nil) = close(table)
    Error(slate.NotFound)
  })
  |> expect.to_equal(Error(slate.NotFound))

  test_helper.did_panic(fn() {
    with_table(path, slate.NoRepair, slate.ReadOnly, fn(_table) {
      panic as "callback failed"
    })
  })
  |> expect.to_equal(True)
  test_helper.is_table_open(path) |> expect.to_equal(False)

  let assert Ok(Nil) = corrupt_byte(path, 11)
  with_table(path, slate.NoRepair, slate.ReadWrite, fn(_table) {
    panic as "callback must not run when repair is required"
  })
  |> expect.to_equal(
    Error(
      slate.NeedsRepair(file_error_test_helper.context(path, "needs_repair")),
    ),
  )
  test_helper.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.ForceRepair, slate.ReadWrite, size)
  |> expect.to_equal(Ok(1))
  test_helper.is_table_open(path) |> expect.to_equal(False)
  test_helper.cleanup(path)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(_table) {
    panic as "callback must not run when the file is missing"
  })
  |> expect.to_equal(
    Error(slate.FileNotFound(file_error_test_helper.context(path, "enoent"))),
  )
  test_helper.is_table_open(path) |> expect.to_equal(False)
}

@external(erlang, "corruption_test_ffi", "corrupt_byte")
fn corrupt_byte(path: String, position: Int) -> Result(Nil, Nil)
