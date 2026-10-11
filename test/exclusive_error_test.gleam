import gleam/list
import gleam/option.{None, Some}
import slate
import slate/exclusive
import startest/expect

pub fn exclusive_error_codes_test() -> Nil {
  exclusive.error_code(exclusive.AcquisitionFailed(exclusive.Busy))
  |> expect.to_equal("lock_busy")
  exclusive.error_code(exclusive.AcquisitionFailed(exclusive.TimedOut))
  |> expect.to_equal("lock_timed_out")
  exclusive.error_code(exclusive.AcquisitionFailed(exclusive.InvalidWait(-1)))
  |> expect.to_equal("invalid_lock_wait")
  exclusive.error_code(
    exclusive.CleanupFailed(Some(exclusive.CallbackFailure(slate.NotFound)), [
      exclusive.CloseFailure(slate.TableDoesNotExist),
    ]),
  )
  |> expect.to_equal("exclusive_cleanup_failed")
}

pub fn exclusive_error_message_omits_native_details_test() -> Nil {
  exclusive.error_message(
    exclusive.AcquisitionFailed(exclusive.NativeUnavailable(
      "private path and native details",
    )),
  )
  |> expect.to_equal("The native table lock component could not be loaded.")
}

pub fn exclusive_error_classifiers_test() -> Nil {
  let context =
    slate.FileErrorContext(
      path: Some("private path"),
      reason: "private native detail",
    )
  let cases = [
    #(exclusive.Busy, "lock_busy", "Another session owns the table."),
    #(exclusive.TimedOut, "lock_timed_out", "The table ownership wait expired."),
    #(
      exclusive.InvalidWait(-1),
      "invalid_lock_wait",
      "The ownership wait must not be negative.",
    ),
    #(
      exclusive.UnsupportedPlatform("private platform detail"),
      "lock_unsupported_platform",
      "Exclusive table sessions are not supported on this platform.",
    ),
    #(
      exclusive.UnsupportedFilesystem(context),
      "lock_unsupported_filesystem",
      "Exclusive table sessions are not supported on this filesystem.",
    ),
    #(
      exclusive.NativeUnavailable("private native detail"),
      "lock_native_unavailable",
      "The native table lock component could not be loaded.",
    ),
    #(
      exclusive.UnsafeAlias(context),
      "lock_unsafe_alias",
      "The table or lock path has an unsafe alias.",
    ),
    #(
      exclusive.OsFailure(context),
      "lock_os_failure",
      "A native table lock operation failed.",
    ),
  ]
  list.each(cases, fn(entry) {
    let #(error, code, message) = entry
    list.each(
      [
        exclusive.AcquisitionFailed(error),
        exclusive.SessionFailed(exclusive.AcquisitionFailure(error)),
      ],
      fn(error) {
        exclusive.error_code(error) |> expect.to_equal(code)
        exclusive.error_message(error) |> expect.to_equal(message)
      },
    )
  })
  list.each(
    [
      exclusive.SessionFailed(exclusive.OpenFailure(slate.NotFound)),
      exclusive.SessionFailed(exclusive.CallbackFailure(slate.NotFound)),
    ],
    fn(error) {
      exclusive.error_code(error)
      |> expect.to_equal(slate.error_code(slate.NotFound))
      exclusive.error_message(error)
      |> expect.to_equal(slate.error_message(slate.NotFound))
    },
  )
  list.each(
    [
      exclusive.CloseFailure(slate.TableDoesNotExist),
      exclusive.ReleaseFailure(exclusive.OsFailure(context)),
      exclusive.GuardianStopped("private guardian detail"),
    ],
    fn(failure) {
      let error = exclusive.CleanupFailed(None, [failure])
      exclusive.error_code(error) |> expect.to_equal("exclusive_cleanup_failed")
      exclusive.error_message(error)
      |> expect.to_equal(
        "Table cleanup failed. Ownership may remain until the VM exits.",
      )
    },
  )
}
