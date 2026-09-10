//// Type-safe Gleam wrapper for Erlang DETS (Disk Erlang Term Storage).
////
//// DETS provides persistent key-value storage backed by files on disk.
//// Stored data persists across node restarts. An abnormal node shutdown can lose
//// pending writes and leave the file needing repair. DETS is built into OTP.
//// No separate database service is required.
////
//// ## Table types
////
//// - `slate/set`: One value per key
//// - `slate/bag`: Multiple distinct values per key
//// - `slate/duplicate_bag`: Multiple values per key, including duplicates
////
//// An entry is one key-value pair. The table modules share a core API.
//// Set and bag tables also provide `insert_new`, with different duplicate
//// rules. Only set tables provide `update_counter`.
////
//// ## Quick start
////
//// ```gleam
//// import gleam/dynamic/decode
//// import slate/set
////
//// let assert Ok(table) = set.open("cache.dets",
////   key_decoder: decode.string, value_decoder: decode.string)
//// let assert Ok(Nil) = set.insert(table, "key", "value")
//// let assert Ok(value) = set.lookup(table, key: "key")
//// let assert Ok(Nil) = set.close(table)
//// ```
////
//// ## Limitations
////
//// - 2 GB maximum file size
//// - No `ordered_set` table type (unlike ETS)
//// - Disk-backed access is slower than ETS for frequent reads
//// - Tables must be closed properly or data may be lost
//// - Bounded table name pool: slate uses a bounded set of internal
////   DETS table names to avoid unbounded atom growth. Opening too many
////   distinct tables at once may fail; close unused tables promptly

import gleam/dynamic/decode
import gleam/option.{type Option}

/// Diagnostic context for an expected file error.
///
/// `path` is the filename reported by OTP, not a table name. For a pathless
/// `AlreadyOpen` error, open operations supply the path they passed to OTP.
/// Open operations normally report an absolute path.
/// `is_dets_file` can report a relative path.
/// `None` means OTP supplied no single filename (for example, a pathless error
/// or a rename failure with two filenames). No table lookup is needed, so
/// context remains usable after the table closes.
///
/// `reason` is the lower-level Erlang reason formatted for diagnostics, such as
/// `"enoent"`, `"{error,eacces}"`, `"access_mode"`, or `"keypos_mismatch"`.
/// Rename failures retain both filenames in this diagnostic string.
/// Do not parse it to identify the error category.
/// Both fields can contain sensitive details. Use `error_code` and
/// `error_message` for safe external output.
pub type FileErrorContext {
  FileErrorContext(path: Option(String), reason: String)
}

/// Errors that can occur during DETS operations.
///
/// Match on the explicit variants for expected cases such as `NotFound`,
/// `AccessDenied(_)`, or `TypeMismatch(_)`.
///
/// Treat `UnexpectedError(detail)` as diagnostic output for logs and debugging
/// only. Its string detail is not part of slate's stable API contract. Use
/// `error_code` or `error_message` when you want a stable classifier or a
/// user-facing message.
pub type DetsError {
  /// No value found for the given key
  NotFound
  /// Table file or a parent directory does not exist
  FileNotFound(FileErrorContext)
  /// Table is already open with a different configuration
  AlreadyOpen(FileErrorContext)
  /// The table does not exist (not open)
  TableDoesNotExist
  /// File exceeds the 2 GB DETS limit
  FileSizeLimitExceeded(FileErrorContext)
  /// Key already exists (for insert_new)
  KeyAlreadyPresent
  /// File access denied, or write operation attempted on a read-only table
  AccessDenied(FileErrorContext)
  /// Table type or key position mismatch (e.g., opening a set file as a bag)
  TypeMismatch(FileErrorContext)
  /// All internal table name slots are in use; close unused tables to free slots
  TableNamePoolExhausted
  /// File exists but is not a valid DETS file
  NotADetsFile(FileErrorContext)
  /// File was not closed cleanly and `NoRepair` was requested
  NeedsRepair(FileErrorContext)
  /// Data read from disk did not match the expected Gleam types
  DecodeErrors(List(decode.DecodeError))
  /// Unexpected OTP or Erlang-level error for logging and diagnostics only.
  UnexpectedError(String)
}

/// Access mode for opening tables.
pub type AccessMode {
  /// Read and write access (default)
  ReadWrite
  /// Read-only access; writes return `AccessDenied`
  ReadOnly
}

/// Auto-repair policy for improperly closed tables.
pub type RepairPolicy {
  /// Attempt repair if needed (default)
  AutoRepair
  /// Repair even if the file was closed properly
  ForceRepair
  /// Return an error if the file needs repair
  NoRepair
}

/// Information about an open DETS table.
///
/// `file_size` is the size of the table file in bytes.
/// `object_count` is the number of stored entries, not the number of distinct
/// keys. In a duplicate bag, each copy of a key-value pair counts as an entry.
/// `file_path` is the absolute path used by `open`, with `.` and `..`
/// segments normalized. Symlinks are not resolved.
pub type TableInfo {
  TableInfo(file_size: Int, object_count: Int, file_path: String)
}

/// Return a stable machine-readable code for a `DetsError`.
///
/// This is useful when you want to log, branch on, or serialize error
/// categories without relying on the detail string in `UnexpectedError(_)`.
pub fn error_code(of error: DetsError) -> String {
  case error {
    NotFound -> "not_found"
    FileNotFound(_) -> "file_not_found"
    AlreadyOpen(_) -> "already_open"
    TableDoesNotExist -> "table_does_not_exist"
    FileSizeLimitExceeded(_) -> "file_size_limit_exceeded"
    KeyAlreadyPresent -> "key_already_present"
    AccessDenied(_) -> "access_denied"
    TypeMismatch(_) -> "type_mismatch"
    TableNamePoolExhausted -> "table_name_pool_exhausted"
    NotADetsFile(_) -> "not_a_dets_file"
    NeedsRepair(_) -> "needs_repair"
    DecodeErrors(_) -> "decode_error"
    UnexpectedError(_) -> "unexpected_error"
  }
}

/// Return a concise user-facing description for a `DetsError`.
///
/// File context and `UnexpectedError(_)` details are intentionally omitted so
/// callers can safely surface messages without leaking paths or OTP details.
pub fn error_message(of error: DetsError) -> String {
  case error {
    NotFound -> "No value was found for the requested key."
    FileNotFound(_) -> "The DETS file could not be found."
    AlreadyOpen(_) -> "The table is already open with incompatible options."
    TableDoesNotExist -> "The table is not currently open."
    FileSizeLimitExceeded(_) -> "The DETS file exceeded the 2 GB size limit."
    KeyAlreadyPresent -> "The key or key-value pair is already present."
    AccessDenied(_) ->
      "The requested operation is not allowed with the current access mode."
    TypeMismatch(_) -> "The file was opened with the wrong DETS table type."
    TableNamePoolExhausted -> "Too many different DETS tables are open at once."
    NotADetsFile(_) -> "The file exists but is not a valid DETS file."
    NeedsRepair(_) ->
      "The table file was not closed cleanly and needs repair. Open with AutoRepair or ForceRepair."
    DecodeErrors(_) -> "Data on disk did not match the expected Gleam types."
    UnexpectedError(_) -> "An unexpected DETS error occurred."
  }
}

/// Check whether the given file is a valid DETS file.
///
/// Returns `Ok(True)` if the file is a valid DETS file, `Ok(False)` if
/// it exists but is not a DETS file, or an error if the file cannot be read.
///
/// This identifies the file type. It does not check every entry or guarantee
/// that opening or decoding will succeed. Apply your own path and access rules
/// before using a path from an untrusted source.
///
/// ```gleam
/// let assert Ok(True) = slate.is_dets_file("data/cache.dets")
/// let assert Ok(False) = slate.is_dets_file("README.md")
/// ```
///
pub fn is_dets_file(path: String) -> Result(Bool, DetsError) {
  ffi_is_dets_file(path)
}

@external(erlang, "slate_dets_ffi", "is_dets_file")
fn ffi_is_dets_file(path: String) -> Result(Bool, DetsError)
