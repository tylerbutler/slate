import gleam/dynamic/decode
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helpers

pub fn set_with_table_options_test() -> Nil {
  check_options(
    "test_set_scoped_options.dets",
    fn(path, repair, access, fun) {
      set.with_table_with(
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
      bag.with_table_with(
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
      duplicate_bag.with_table_with(
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
  test_helpers.cleanup(path)
  with_table(path, slate.NoRepair, slate.ReadWrite, fn(table) {
    let assert Ok(Nil) = insert(table, "key", 42)
    Ok(42)
  })
  |> expect.to_equal(Ok(42))
  test_helpers.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(table) {
    insert(table, "other", 99) |> expect.to_equal(Error(slate.AccessDenied))
    size(table)
  })
  |> expect.to_equal(Ok(1))
  test_helpers.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(_table) {
    Error(slate.NotFound)
  })
  |> expect.to_equal(Error(slate.NotFound))
  test_helpers.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(table) {
    let assert Ok(Nil) = close(table)
    Ok(42)
  })
  |> expect.to_equal(Error(slate.UnexpectedError("not_owner")))

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(table) {
    let assert Ok(Nil) = close(table)
    Error(slate.NotFound)
  })
  |> expect.to_equal(Error(slate.NotFound))

  test_helpers.did_panic(fn() {
    with_table(path, slate.NoRepair, slate.ReadOnly, fn(_table) {
      panic as "callback failed"
    })
  })
  |> expect.to_equal(True)
  test_helpers.is_table_open(path) |> expect.to_equal(False)

  let assert Ok(Nil) = corrupt_byte(path, 11)
  with_table(path, slate.NoRepair, slate.ReadWrite, fn(_table) {
    panic as "callback must not run when repair is required"
  })
  |> expect.to_equal(Error(slate.NeedsRepair))
  test_helpers.is_table_open(path) |> expect.to_equal(False)

  with_table(path, slate.ForceRepair, slate.ReadWrite, size)
  |> expect.to_equal(Ok(1))
  test_helpers.is_table_open(path) |> expect.to_equal(False)
  test_helpers.cleanup(path)

  with_table(path, slate.NoRepair, slate.ReadOnly, fn(_table) {
    panic as "callback must not run when the file is missing"
  })
  |> expect.to_equal(Error(slate.FileNotFound))
  test_helpers.is_table_open(path) |> expect.to_equal(False)
}

@external(erlang, "corruption_test_ffi", "corrupt_byte")
fn corrupt_byte(path: String, position: Int) -> Result(Nil, Nil)
