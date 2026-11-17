import gleam/dynamic/decode
import gleam/list
import slate
import slate/bag
import slate/duplicate_bag
import slate/exclusive
import slate/set
import test_helper

pub fn is_dets_file_unicode_no_fallback_test() -> Nil {
  let path = "test_is_dets_filename_caf\u{e9}.dets"
  let legacy = "test_is_dets_filename_caf\u{c3}\u{a9}.dets"
  list.each([path, legacy], test_helper.cleanup)
  let assert Ok(Nil) =
    set.with_exclusive_table(
      path: legacy,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(table) { set.insert(table, "legacy", 99) },
    )
  let assert Error(slate.FileNotFound(_)) = slate.is_dets_file(path)
  assert !is_regular(path)
  assert slate.is_dets_file(legacy) == Ok(True)
  list.each([path, legacy, legacy <> ".slate.lock"], test_helper.cleanup)
}

pub fn set_unicode_filename_test() -> Nil {
  check_filename(
    "test_set_filename",
    fn(path) {
      set.open(path, key_decoder: decode.string, value_decoder: decode.int)
    },
    fn(path, access) {
      set.open_with_access(
        path,
        slate.NoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    fn(path, access, callback) {
      set.with_exclusive_table(
        path:,
        repair: slate.NoRepair,
        access:,
        wait: exclusive.Immediate,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    set.insert,
    set.to_list,
    set.close,
  )
}

pub fn bag_unicode_filename_test() -> Nil {
  check_filename(
    "test_bag_filename",
    fn(path) {
      bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
    },
    fn(path, access) {
      bag.open_with_access(
        path,
        slate.NoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    fn(path, access, callback) {
      bag.with_exclusive_table(
        path:,
        repair: slate.NoRepair,
        access:,
        wait: exclusive.Immediate,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    bag.insert,
    bag.to_list,
    bag.close,
  )
}

pub fn duplicate_bag_unicode_filename_test() -> Nil {
  check_filename(
    "test_duplicate_bag_filename",
    fn(path) {
      duplicate_bag.open(
        path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    fn(path, access) {
      duplicate_bag.open_with_access(
        path,
        slate.NoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    fn(path, access, callback) {
      duplicate_bag.with_exclusive_table(
        path:,
        repair: slate.NoRepair,
        access:,
        wait: exclusive.Immediate,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    duplicate_bag.insert,
    duplicate_bag.to_list,
    duplicate_bag.close,
  )
}

fn check_filename(
  prefix: String,
  open: fn(String) -> Result(table, slate.DetsError),
  open_with_access: fn(String, slate.AccessMode) ->
    Result(table, slate.DetsError),
  session: fn(
    String,
    slate.AccessMode,
    fn(table) -> Result(Nil, slate.DetsError),
  ) -> Result(Nil, exclusive.SessionError),
  insert: fn(table, String, Int) -> Result(Nil, slate.DetsError),
  to_list: fn(table) -> Result(List(#(String, Int)), slate.DetsError),
  close: fn(table) -> Result(Nil, slate.DetsError),
) -> Nil {
  // BMP code points also exercise OTP 27's Windows filename-list encoder.
  let path = prefix <> "_caf\u{e9}_\u{4e2d}.dets"
  let legacy = prefix <> "_caf\u{c3}\u{a9}_\u{e4}\u{b8}\u{ad}.dets"
  list.each([path, legacy], test_helper.cleanup)

  let assert Ok(table) = open(path)
  let assert Ok(Nil) = insert(table, "key", 42)
  let assert Ok(Nil) = close(table)
  assert is_regular(path)
  assert !is_regular(legacy)
  assert slate.is_dets_file(path) == Ok(True)
  list.each([slate.ReadOnly, slate.ReadWrite], fn(access) {
    assert session(path, access, fn(table) {
        assert to_list(table) == Ok([#("key", 42)])
        Ok(Nil)
      })
      == Ok(Nil)
  })
  test_helper.cleanup(path)

  // Exclusive sessions create a correctly named file independently of open.
  assert session(path, slate.ReadWrite, fn(table) { insert(table, "key", 73) })
    == Ok(Nil)
  assert is_regular(path)
  assert slate.is_dets_file(path) == Ok(True)
  list.each([slate.ReadOnly, slate.ReadWrite], fn(access) {
    let assert Ok(table) = open_with_access(path, access)
    assert to_list(table) == Ok([#("key", 73)])
    let assert Ok(Nil) = close(table)
  })
  let assert Ok(table) = open(path)
  assert to_list(table) == Ok([#("key", 73)])
  let assert Ok(Nil) = close(table)

  // Both names can contain different datasets. Never select the legacy name.
  assert session(legacy, slate.ReadWrite, fn(table) {
      insert(table, "legacy", 99)
    })
    == Ok(Nil)
  let assert Ok(table) = open(path)
  assert to_list(table) == Ok([#("key", 73)])
  let assert Ok(Nil) = close(table)
  test_helper.cleanup(path)
  let assert Error(_) = open_with_access(path, slate.ReadOnly)
  let assert Error(exclusive.SessionFailed(exclusive.OpenFailure(slate.FileNotFound(
    _,
  )))) = session(path, slate.ReadOnly, fn(_) { panic as "legacy fallback" })
  assert !is_regular(path)
  let assert Ok(table) = open(path)
  assert to_list(table) == Ok([])
  let assert Ok(Nil) = close(table)
  assert is_regular(path)
  assert session(legacy, slate.ReadOnly, fn(table) {
      assert to_list(table) == Ok([#("legacy", 99)])
      Ok(Nil)
    })
    == Ok(Nil)
  list.each(
    [path, legacy, path <> ".slate.lock", legacy <> ".slate.lock"],
    test_helper.cleanup,
  )
}

@external(erlang, "filelib", "is_regular")
fn is_regular(path: String) -> Bool
