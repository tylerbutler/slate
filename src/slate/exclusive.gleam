//// Configuration and errors for exclusive table sessions.
////
//// All clients of a shared file, including readers, must use exclusive
//// sessions. Unlocked Slate APIs and raw DETS do not participate.

import gleam/option.{type Option}
import slate.{type DetsError, type FileErrorContext}

/// How long to wait for ownership. This does not limit an acquired session.
pub type Wait {
  /// Try once without waiting for another owner.
  Immediate
  /// Wait up to this many milliseconds. Zero means `Immediate`.
  /// Negative values return `InvalidWait`.
  WaitUpTo(milliseconds: Int)
}

/// A failure to acquire or release native ownership.
pub type LockError {
  /// Another session owns the file.
  Busy
  /// Ownership was not acquired before the acquisition deadline.
  TimedOut
  /// The acquisition wait was negative.
  InvalidWait(milliseconds: Int)
  /// The OS, architecture, or C runtime is not supported.
  UnsupportedPlatform(detail: String)
  /// The file is not on a qualified local filesystem.
  UnsupportedFilesystem(context: FileErrorContext)
  /// A native artifact is missing, incompatible, or cannot be loaded.
  NativeUnavailable(detail: String)
  /// A hard link, unsafe sidecar, or changed path prevents safe ownership.
  UnsafeAlias(context: FileErrorContext)
  /// An OS operation failed. Context is for trusted diagnostics only.
  OsFailure(context: FileErrorContext)
}

/// The primary failure before cleanup.
pub type SessionFailure {
  /// Acquisition failed and releasing a late lock also failed.
  AcquisitionFailure(LockError)
  /// DETS could not open or repair the file.
  OpenFailure(DetsError)
  /// The callback returned an error. Earlier writes are not rolled back.
  CallbackFailure(DetsError)
}

/// A cleanup failure. Ownership may remain until the VM exits.
pub type CleanupFailure {
  /// DETS did not confirm a clean close.
  CloseFailure(DetsError)
  /// The native lock could not be released.
  ReleaseFailure(LockError)
  /// The session guardian stopped unexpectedly.
  GuardianStopped(detail: String)
}

/// Errors from `with_exclusive_table`.
///
/// A successful result confirms close and lock release. `CleanupFailed`
/// preserves both primary and cleanup failures. After a callback exception,
/// cleanup failures are logged and the original exception is re-raised.
pub type SessionError {
  AcquisitionFailed(LockError)
  SessionFailed(SessionFailure)
  CleanupFailed(primary: Option(SessionFailure), failures: List(CleanupFailure))
}

/// Return a stable code without paths or native diagnostic details.
pub fn error_code(error: SessionError) -> String {
  case error {
    AcquisitionFailed(Busy) -> "lock_busy"
    AcquisitionFailed(TimedOut) -> "lock_timed_out"
    AcquisitionFailed(InvalidWait(_)) -> "invalid_lock_wait"
    AcquisitionFailed(UnsupportedPlatform(_)) -> "lock_unsupported_platform"
    AcquisitionFailed(UnsupportedFilesystem(_)) -> "lock_unsupported_filesystem"
    AcquisitionFailed(NativeUnavailable(_)) -> "lock_native_unavailable"
    AcquisitionFailed(UnsafeAlias(_)) -> "lock_unsafe_alias"
    AcquisitionFailed(OsFailure(_)) -> "lock_os_failure"
    SessionFailed(OpenFailure(error)) -> slate.error_code(error)
    SessionFailed(CallbackFailure(error)) -> slate.error_code(error)
    SessionFailed(AcquisitionFailure(error)) ->
      error_code(AcquisitionFailed(error))
    CleanupFailed(_, _) -> "exclusive_cleanup_failed"
  }
}

/// Return a user-facing message without diagnostic details.
pub fn error_message(error: SessionError) -> String {
  case error {
    AcquisitionFailed(Busy) -> "Another session owns the table."
    AcquisitionFailed(TimedOut) -> "The table ownership wait expired."
    AcquisitionFailed(InvalidWait(_)) ->
      "The ownership wait must not be negative."
    AcquisitionFailed(UnsupportedPlatform(_)) ->
      "Exclusive table sessions are not supported on this platform."
    AcquisitionFailed(UnsupportedFilesystem(_)) ->
      "Exclusive table sessions are not supported on this filesystem."
    AcquisitionFailed(NativeUnavailable(_)) ->
      "The native table lock component could not be loaded."
    AcquisitionFailed(UnsafeAlias(_)) ->
      "The table or lock path has an unsafe alias."
    AcquisitionFailed(OsFailure(_)) -> "A native table lock operation failed."
    SessionFailed(OpenFailure(error)) -> slate.error_message(error)
    SessionFailed(CallbackFailure(error)) -> slate.error_message(error)
    SessionFailed(AcquisitionFailure(error)) ->
      error_message(AcquisitionFailed(error))
    CleanupFailed(_, _) ->
      "Table cleanup failed. Ownership may remain until the VM exits."
  }
}
