import gleam/option.{Some}
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
