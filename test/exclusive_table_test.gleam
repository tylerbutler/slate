import gleam/dynamic/decode
import gleam/option.{Some}
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/exclusive
import slate/set
import test_helper

pub fn set_exclusive_table_test() -> Nil {
  check_session(
    "test_set_exclusive.dets",
    fn(path, repair, access, wait, callback) {
      set.with_exclusive_table(
        path:,
        repair:,
        access:,
        wait:,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    set.insert,
    set.size,
  )
}

pub fn bag_exclusive_table_test() -> Nil {
  check_session(
    "test_bag_exclusive.dets",
    fn(path, repair, access, wait, callback) {
      bag.with_exclusive_table(
        path:,
        repair:,
        access:,
        wait:,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    bag.insert,
    bag.size,
  )
}

pub fn duplicate_bag_exclusive_table_test() -> Nil {
  check_session(
    "test_duplicate_bag_exclusive.dets",
    fn(path, repair, access, wait, callback) {
      duplicate_bag.with_exclusive_table(
        path:,
        repair:,
        access:,
        wait:,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    duplicate_bag.insert,
    duplicate_bag.size,
  )
}

fn check_session(
  path: String,
  session: fn(
    String,
    slate.RepairPolicy,
    slate.AccessMode,
    exclusive.Wait,
    fn(table) -> Result(Int, slate.DetsError),
  ) -> Result(Int, exclusive.SessionError),
  insert: fn(table, String, Int) -> Result(Nil, slate.DetsError),
  size: fn(table) -> Result(Int, slate.DetsError),
) -> Nil {
  test_helper.cleanup(path)
  let assert True =
    session(
      path,
      slate.NoRepair,
      slate.ReadWrite,
      exclusive.Immediate,
      fn(table) {
        let assert Ok(Nil) = insert(table, "key", 42)
        size(table)
      },
    )
    == Ok(1)
  let assert True = test_helper.is_table_open(path) == False

  let assert True =
    session(
      path,
      slate.NoRepair,
      slate.ReadOnly,
      exclusive.WaitUpTo(1000),
      size,
    )
    == Ok(1)

  let assert True =
    session(
      path,
      slate.NoRepair,
      slate.ReadWrite,
      exclusive.Immediate,
      fn(table) {
        let assert True =
          session(
            path,
            slate.NoRepair,
            slate.ReadOnly,
            exclusive.Immediate,
            fn(_) { panic as "nested session callback must not run" },
          )
          == Error(exclusive.AcquisitionFailed(exclusive.Busy))
        size(table)
      },
    )
    == Ok(1)

  let assert Error(exclusive.SessionFailed(exclusive.CallbackFailure(slate.AccessDenied(
    _,
  )))) =
    session(
      path,
      slate.NoRepair,
      slate.ReadOnly,
      exclusive.Immediate,
      fn(table) {
        let assert Error(error) = insert(table, "readonly", 1)
        Error(error)
      },
    )

  let assert True =
    session(
      path,
      slate.NoRepair,
      slate.ReadOnly,
      exclusive.WaitUpTo(0),
      fn(_table) { Error(slate.NotFound) },
    )
    == Error(exclusive.SessionFailed(exclusive.CallbackFailure(slate.NotFound)))
  let assert True = test_helper.is_table_open(path) == False

  let assert True =
    session(path, slate.NoRepair, slate.ReadOnly, exclusive.WaitUpTo(-1), fn(_) {
      panic as "invalid acquisition must not run the callback"
    })
    == Error(exclusive.AcquisitionFailed(exclusive.InvalidWait(-1)))

  let assert True =
    test_helper.did_panic(fn() {
      session(path, slate.NoRepair, slate.ReadWrite, exclusive.Immediate, fn(_) {
        panic as "exclusive callback failed"
      })
    })
    == True
  let assert True = test_helper.is_table_open(path) == False
  let assert True =
    session(path, slate.NoRepair, slate.ReadOnly, exclusive.Immediate, size)
    == Ok(1)
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_open_failure_does_not_call_callback_test() -> Nil {
  let path = "test_exclusive_missing.dets"
  test_helper.cleanup(path)
  let result =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadOnly,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(_) { panic as "missing table callback must not run" },
    )
  let assert Error(exclusive.SessionFailed(exclusive.OpenFailure(slate.FileNotFound(
    _,
  )))) = result
  let assert Ok(0) =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: set.size,
    )
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_rejects_existing_unlocked_table_test() -> Nil {
  let path = "test_exclusive_existing.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let result =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(_) { panic as "existing table callback must not run" },
    )
  let assert Error(exclusive.SessionFailed(exclusive.OpenFailure(slate.AlreadyOpen(
    _,
  )))) = result
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_context_error_message_test() -> Nil {
  let assert True =
    exclusive.error_message(
      exclusive.AcquisitionFailed(
        exclusive.OsFailure(slate.FileErrorContext(
          Some("private-path"),
          "private-reason",
        )),
      ),
    )
    == "A native table lock operation failed."
  Nil
}

pub fn exclusive_decoder_failure_test() -> Nil {
  let path = "test_exclusive_decoder.dets"
  let assert Ok(Nil) =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.string,
      callback: fn(table) { set.insert(table, "key", "wrong type") },
    )
  let assert Error(exclusive.SessionFailed(exclusive.CallbackFailure(slate.DecodeErrors([
    _,
    ..
  ])))) =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadOnly,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(table) { set.lookup(table, "key") },
    )
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_unicode_info_and_error_test() -> Nil {
  let path = "test_exclusive_caf\u{00e9}.dets"
  let assert Ok(info) =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: set.info,
    )
  let assert True = string.ends_with(info.file_path, path) == True
  test_helper.cleanup(path)
  let assert Error(exclusive.SessionFailed(exclusive.OpenFailure(slate.FileNotFound(slate.FileErrorContext(
    Some(missing_path),
    _,
  ))))) =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadOnly,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(_) { panic as "missing unicode callback ran" },
    )
  let assert True = string.ends_with(missing_path, path) == True
  cleanup_sidecar(path)
}

@external(erlang, "exclusive_test_ffi", "cleanup_sidecar")
fn cleanup_sidecar(path: String) -> Nil
