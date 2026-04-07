/// Type-safe Gleam wrapper for Erlang DETS (Disk Erlang Term Storage).
///
/// DETS provides persistent key-value storage backed by files on disk.
/// Tables survive process crashes and node restarts. DETS is built into
/// OTP — no external database or dependency is needed.
///
/// ## Table Types
///
/// - `slate/set` — Unique keys, one value per key
/// - `slate/bag` — Multiple distinct values per key
/// - `slate/duplicate_bag` — Multiple values per key (duplicates allowed)
///
/// ## Quick Start
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate/set
///
/// let assert Ok(table) = set.open("data/cache.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(Nil) = set.insert(table, "key", "value")
/// let assert Ok(value) = set.lookup(table, "key")
/// let assert Ok(Nil) = set.close(table)
/// ```
///
/// ## Limitations
///
/// - 2 GB maximum file size
/// - No `ordered_set` table type (unlike ETS)
/// - Disk I/O on every operation (use ETS for high-frequency reads)
/// - Tables must be closed properly or data may be lost
/// - **Bounded table name pool**: slate uses a bounded set of internal
///   DETS table names to avoid unbounded atom growth. Opening too many
///   distinct tables at once may fail; close unused tables promptly
import gleam/dynamic/decode

/// Errors that can occur during DETS operations.
///
/// Match on the explicit variants for expected cases such as `NotFound`,
/// `AccessDenied`, or `TypeMismatch`.
///
/// Treat `UnexpectedError(detail)` as diagnostic output for logs and debugging
/// only. Its string detail is not part of slate's stable API contract. Use
/// `error_code` or `error_message` when you want a stable classifier or a
/// user-facing message.
pub type DetsError {
  /// No value found for the given key
  NotFound
  /// Table file does not exist (when opening without create)
  FileNotFound
  /// The file exists but is not a valid DETS file
  NotADetsFile
  /// The file needs DETS repair before it can be opened with the current policy
  NeedsRepair
  /// Table is already open with a different configuration
  AlreadyOpen
  /// The table does not exist (not open)
  TableDoesNotExist
  /// File exceeds the 2 GB DETS limit
  FileSizeLimitExceeded
  /// Key already exists (for insert_new)
  KeyAlreadyPresent
  /// Write operation attempted on a read-only table
  AccessDenied
  /// Table type mismatch (e.g., opening a set file as a bag)
  TypeMismatch
  /// All internal table name slots are in use; close unused tables to free slots
  TableNamePoolExhausted
  /// Data read from disk did not match the expected Gleam types
  DecodeErrors(List(decode.DecodeError))
  /// Unexpected OTP or Erlang-level error for logging and diagnostics only.
  UnexpectedError(String)
}

/// Access mode for opening tables.
pub type AccessMode {
  /// Read and write access (default)
  ReadWrite
  /// Read-only access — writes will return `AccessDenied`
  ReadOnly
}

/// Auto-repair policy for improperly closed tables.
pub type RepairPolicy {
  /// Repair automatically if needed (default)
  AutoRepair
  /// Force repair even if file appears clean
  ForceRepair
  /// Don't repair, return error instead
  NoRepair
}

/// Information about an open DETS table.
pub type TableInfo {
  TableInfo(file_size: Int, object_count: Int)
}

/// Return a stable machine-readable code for a `DetsError`.
///
/// This is useful when you want to log, branch on, or serialize error
/// categories without relying on the detail string in `UnexpectedError(_)`.
pub fn error_code(of error: DetsError) -> String {
  case error {
    NotFound -> "not_found"
    FileNotFound -> "file_not_found"
    NotADetsFile -> "not_a_dets_file"
    NeedsRepair -> "needs_repair"
    AlreadyOpen -> "already_open"
    TableDoesNotExist -> "table_does_not_exist"
    FileSizeLimitExceeded -> "file_size_limit_exceeded"
    KeyAlreadyPresent -> "key_already_present"
    AccessDenied -> "access_denied"
    TypeMismatch -> "type_mismatch"
    TableNamePoolExhausted -> "table_name_pool_exhausted"
    DecodeErrors(_) -> "decode_error"
    UnexpectedError(_) -> "unexpected_error"
  }
}

/// Return a concise user-facing description for a `DetsError`.
///
/// `UnexpectedError(_)` intentionally maps to a generic message so callers can
/// safely surface it without leaking raw Erlang/OTP diagnostic details.
pub fn error_message(of error: DetsError) -> String {
  case error {
    NotFound -> "No value was found for the requested key."
    FileNotFound -> "The DETS file could not be found."
    NotADetsFile -> "The file exists but is not a valid DETS table."
    NeedsRepair ->
      "The DETS file needs repair before it can be opened with this repair policy."
    AlreadyOpen -> "The table is already open with incompatible options."
    TableDoesNotExist -> "The table is not currently open."
    FileSizeLimitExceeded -> "The DETS file exceeded the 2 GB size limit."
    KeyAlreadyPresent -> "The key or key-value pair is already present."
    AccessDenied ->
      "The requested operation is not allowed with the current access mode."
    TypeMismatch -> "The file was opened with the wrong DETS table type."
    TableNamePoolExhausted -> "Too many different DETS tables are open at once."
    DecodeErrors(_) -> "Data on disk did not match the expected Gleam types."
    UnexpectedError(_) -> "An unexpected DETS error occurred."
  }
}

/// Check whether the given file is a valid DETS file.
///
/// Returns `Ok(True)` if the file is a valid DETS file, `Ok(False)` if
/// it exists but is not a DETS file, or an error if the file cannot be read.
///
/// ```gleam
/// let assert Ok(True) = slate.is_dets_file("data/cache.dets")
/// let assert Ok(False) = slate.is_dets_file("README.md")
/// ```
///
pub fn is_dets_file(path: String) -> Result(Bool, DetsError) {
  ffi_is_dets_file(path)
}

@external(erlang, "dets_ffi", "is_dets_file")
fn ffi_is_dets_file(path: String) -> Result(Bool, DetsError)
