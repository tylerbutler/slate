import file_error_test_helper
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helper

pub fn file_error_context_nested_otp_reasons_test() -> Nil {
  let path = "private/é_資料.dets"
  file_errors(path)
  |> list.each(fn(test_case) {
    let #(error, code, reason) = test_case
    let assert Ok(context) = file_context(error)
    context |> expect.to_equal(slate.FileErrorContext(Some(path), reason))
    slate.error_code(error) |> expect.to_equal(code)
  })
}

pub fn file_error_context_pathless_otp_errors_test() -> Nil {
  pathless_errors()
  |> expect.to_equal([
    slate.NotADetsFile(slate.FileErrorContext(None, "not_a_dets_file")),
    slate.NeedsRepair(slate.FileErrorContext(None, "needs_repair")),
    slate.AccessDenied(slate.FileErrorContext(None, "eacces")),
    slate.AlreadyOpen(slate.FileErrorContext(None, "incompatible_arguments")),
    slate.AlreadyOpen(slate.FileErrorContext(
      None,
      "{incompatible_arguments,slate_context_table}",
    )),
    slate.TableDoesNotExist,
    slate.TableDoesNotExist,
  ])
}

pub fn file_error_context_unknown_reason_stays_unexpected_test() -> Nil {
  let assert slate.UnexpectedError(detail) = unknown_error()
  detail
  |> expect.to_equal("{file_error,<<\"private.dets\">>,{error,enospc}}")
}

pub fn file_error_context_rename_retains_both_paths_test() -> Nil {
  let assert slate.AccessDenied(context) = rename_error()
  context
  |> expect.to_equal(slate.FileErrorContext(
    None,
    "{file_error,{\"old.dets\",\"new.dets\"},eacces}",
  ))
}

pub fn file_error_context_missing_parent_test() -> Nil {
  let path = "missing_context_é_資料/absent.dets"
  let assert Error(slate.FileNotFound(context)) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  context |> expect.to_equal(file_error_test_helper.context(path, "enoent"))
  test_helper.is_table_open(path) |> expect.to_equal(False)
}

pub fn file_error_context_set_conflicting_options_test() -> Nil {
  check_conflicting_options(
    "test_context_set_conflict.dets",
    fn(path, access) {
      set.open_with_access(
        path:,
        repair: slate.AutoRepair,
        access:,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    set.close,
  )
}

pub fn file_error_context_bag_conflicting_options_test() -> Nil {
  check_conflicting_options(
    "test_context_bag_conflict.dets",
    fn(path, access) {
      bag.open_with_access(
        path:,
        repair: slate.AutoRepair,
        access:,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    bag.close,
  )
}

pub fn file_error_context_duplicate_bag_conflicting_options_test() -> Nil {
  check_conflicting_options(
    "test_context_duplicate_bag_conflict.dets",
    fn(path, access) {
      duplicate_bag.open_with_access(
        path:,
        repair: slate.AutoRepair,
        access:,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    },
    duplicate_bag.close,
  )
}

fn check_conflicting_options(
  path: String,
  open: fn(String, slate.AccessMode) -> Result(table, slate.DetsError),
  close: fn(table) -> Result(Nil, slate.DetsError),
) -> Nil {
  let assert Ok(table) = open(path, slate.ReadWrite)
  let assert Error(slate.AlreadyOpen(context)) =
    open("./unused/../" <> path, slate.ReadOnly)
  let assert Ok(Nil) = close(table)
  test_helper.is_table_open(path) |> expect.to_equal(False)
  context
  |> expect.to_equal(file_error_test_helper.context(
    path,
    "incompatible_arguments",
  ))
  let assert Ok(table) = open(path, slate.ReadOnly)
  let assert Ok(Nil) = close(table)
  test_helper.cleanup(path)
}

pub fn file_error_context_readonly_counter_test() -> Nil {
  let path = "test_context_readonly_counter.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "hits", 10)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(table) =
    set.open_with_access(
      path:,
      repair: slate.AutoRepair,
      access: slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Error(set.TableError(slate.AccessDenied(context))) =
    set.update_counter(table, "hits", 1)
  let assert Ok(10) = set.lookup(table, "hits")
  let assert Ok(Nil) = set.close(table)
  // Context does not depend on a live table or table-name pool slot.
  context
  |> expect.to_equal(file_error_test_helper.context(path, "access_mode"))
  test_helper.is_table_open(path) |> expect.to_equal(False)
  test_helper.cleanup(path)
}

pub fn file_error_context_closed_set_operations_test() -> Nil {
  let path = "test_context_closed_set.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.close(table)
  set.lookup(table, "key") |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.member(table, "key") |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.to_list(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.fold(table, 0, fn(acc, _, _) { acc })
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.fold_results(table, 0, fn(acc, _) { acc })
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.insert(table, "key", 1)
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.delete_key(table, "key")
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.sync(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  set.info(table) |> expect.to_equal(Error(slate.TableDoesNotExist))
  expect_closed_close(set.close(table))
  test_helper.is_table_open(path) |> expect.to_equal(False)
  test_helper.cleanup(path)
}

pub fn file_error_context_closed_bags_test() -> Nil {
  let path = "test_context_closed_bag.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.close(table)
  bag.lookup(table, "key") |> expect.to_equal(Error(slate.TableDoesNotExist))
  bag.insert(table, "key", 1)
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  expect_closed_close(bag.close(table))
  test_helper.is_table_open(path) |> expect.to_equal(False)
  test_helper.cleanup(path)

  let path = "test_context_closed_duplicate_bag.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.close(table)
  duplicate_bag.lookup(table, "key")
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  duplicate_bag.insert(table, "key", 1)
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  expect_closed_close(duplicate_bag.close(table))
  test_helper.is_table_open(path) |> expect.to_equal(False)
  test_helper.cleanup(path)
}

pub fn file_error_context_with_table_cleanup_test() -> Nil {
  let path = "test_context_callback.dets"
  let missing = "missing_context_callback/absent.dets"
  let result =
    set.with_table(
      path,
      slate.NoRepair,
      slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(table) {
        let assert Ok(Nil) = set.insert(table, "key", 1)
        slate.is_dets_file(missing)
      },
    )
  result
  |> expect.to_equal(
    Error(slate.FileNotFound(slate.FileErrorContext(Some(missing), "enoent"))),
  )
  test_helper.is_table_open(path) |> expect.to_equal(False)
  // The callback error did not prevent a clean, readable close.
  let assert Ok(table) =
    set.open_with(
      path,
      slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(1) = set.lookup(table, "key")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn file_error_context_stable_safe_codes_and_messages_test() -> Nil {
  [None, Some("/private/customer\nsecret.dets")]
  |> list.each(fn(path) {
    let context = slate.FileErrorContext(path, "sensitive OTP detail")
    [
      #(
        slate.NotFound,
        "not_found",
        "No value was found for the requested key.",
      ),
      #(
        slate.FileNotFound(context),
        "file_not_found",
        "The DETS file could not be found.",
      ),
      #(
        slate.AlreadyOpen(context),
        "already_open",
        "The table is already open with incompatible options.",
      ),
      #(
        slate.TableDoesNotExist,
        "table_does_not_exist",
        "The table is not currently open.",
      ),
      #(
        slate.FileSizeLimitExceeded(context),
        "file_size_limit_exceeded",
        "The DETS file exceeded the 2 GB size limit.",
      ),
      #(
        slate.KeyAlreadyPresent,
        "key_already_present",
        "The key or key-value pair is already present.",
      ),
      #(
        slate.AccessDenied(context),
        "access_denied",
        "The requested operation is not allowed with the current access mode.",
      ),
      #(
        slate.TypeMismatch(context),
        "type_mismatch",
        "The file was opened with the wrong DETS table type.",
      ),
      #(
        slate.TableNamePoolExhausted,
        "table_name_pool_exhausted",
        "Too many different DETS tables are open at once.",
      ),
      #(
        slate.NotADetsFile(context),
        "not_a_dets_file",
        "The file exists but is not a valid DETS file.",
      ),
      #(
        slate.NeedsRepair(context),
        "needs_repair",
        "The table file was not closed cleanly and needs repair. Open with AutoRepair or ForceRepair.",
      ),
      #(
        slate.DecodeErrors([]),
        "decode_error",
        "Data on disk did not match the expected Gleam types.",
      ),
      #(
        slate.UnexpectedError("sensitive OTP detail"),
        "unexpected_error",
        "An unexpected DETS error occurred.",
      ),
    ]
    |> list.each(fn(test_case) {
      let #(error, code, message) = test_case
      slate.error_code(error) |> expect.to_equal(code)
      slate.error_message(error) |> expect.to_equal(message)
    })
  })
}

fn file_context(error: slate.DetsError) -> Result(slate.FileErrorContext, Nil) {
  case error {
    slate.FileNotFound(context)
    | slate.AlreadyOpen(context)
    | slate.AccessDenied(context)
    | slate.TypeMismatch(context)
    | slate.NeedsRepair(context)
    | slate.NotADetsFile(context)
    | slate.FileSizeLimitExceeded(context) -> Ok(context)
    slate.NotFound
    | slate.KeyAlreadyPresent
    | slate.TableDoesNotExist
    | slate.TableNamePoolExhausted
    | slate.DecodeErrors(_)
    | slate.UnexpectedError(_) -> Error(Nil)
  }
}

fn expect_closed_close(result: Result(Nil, slate.DetsError)) -> Nil {
  // A second close can see a missing owner or an already removed table.
  // Keep these existing classifications; neither has file context.
  list.contains(
    [
      Error(slate.TableDoesNotExist),
      Error(slate.UnexpectedError("not_owner")),
    ],
    result,
  )
  |> expect.to_be_true()
}

@external(erlang, "file_error_test_ffi", "file_errors")
fn file_errors(path: String) -> List(#(slate.DetsError, String, String))

@external(erlang, "file_error_test_ffi", "pathless_errors")
fn pathless_errors() -> List(slate.DetsError)

@external(erlang, "file_error_test_ffi", "unknown_error")
fn unknown_error() -> slate.DetsError

@external(erlang, "file_error_test_ffi", "rename_error")
fn rename_error() -> slate.DetsError
