/// Type-safe Gleam wrapper for Erlang DETS (Disk Erlang Term Storage).
///
/// DETS provides persistent key-value storage backed by files on disk.
/// Tables survive process crashes and node restarts. DETS is built into
/// OTP — no external database or dependency is needed.
///
/// ## Table Types
///
/// - `dets/set` — Unique keys, one value per key
/// - `dets/bag` — Multiple distinct values per key
/// - `dets/duplicate_bag` — Multiple values per key (duplicates allowed)
///
/// ## Quick Start
///
/// ```gleam
/// import dets/set
///
/// let assert Ok(table) = set.open("data/cache.dets")
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
///
/// Errors that can occur during DETS operations.
pub type DetsError {
  /// No value found for the given key
  NotFound
  /// Table file does not exist (when opening without create)
  FileNotFound
  /// Table is already open with a different configuration
  AlreadyOpen
  /// The table does not exist (not open)
  TableDoesNotExist
  /// File exceeds the 2 GB DETS limit
  FileSizeLimitExceeded
  /// Key already exists (for insert_new)
  KeyAlreadyPresent
  /// Erlang-level error (catch-all)
  ErlangError(String)
}

/// DETS table type.
pub type Kind {
  /// One value per key (default)
  Set
  /// Multiple distinct values per key
  Bag
  /// Multiple values per key, duplicates allowed
  DuplicateBag
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
  TableInfo(file_size: Int, object_count: Int, kind: Kind)
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
