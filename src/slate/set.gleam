//// DETS set tables: one value per key.
////
//// Set tables store key-value pairs where each key maps to exactly one value.
//// Inserting with an existing key overwrites the previous value.
////
//// ## Example
////
//// ```gleam
//// import gleam/dynamic/decode
//// import slate/set
////
//// let assert Ok(table) = set.open("users.dets",
////   key_decoder: decode.string, value_decoder: decode.int)
//// let assert Ok(Nil) = set.insert(table, "alice", 42)
//// let assert Ok(42) = set.lookup(table, "alice")
//// let assert Ok(Nil) = set.close(table)
//// ```
////

import gleam/dynamic/decode.{type Decoder, type Dynamic}

import gleam/result
import slate.{type AccessMode, type DetsError, type RepairPolicy, AutoRepair}
import slate/internal

/// Errors returned by `update_counter`.
pub type UpdateCounterError {
  /// `update_counter` requires the stored value to be an integer.
  CounterValueNotInteger
  /// A shared DETS table error from the underlying operation.
  TableError(DetsError)
}

/// An open DETS set table with typed keys and values.
pub opaque type Set(k, v) {
  Set(
    reference: TableReference,
    key_decoder: Decoder(k),
    value_decoder: Decoder(v),
  )
}

/// Internal reference to the DETS table (Erlang atom).
type TableReference

type UpdateCounterFfiError {
  FfiCounterValueNotInteger
  FfiTableError(DetsError)
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open or create a DETS set table at the given file path.
///
/// The parent directory must exist. This function uses `AutoRepair` and
/// `ReadWrite`.
///
/// Reads use your decoders to check stored data. Opening a table does not
/// check all its entries.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = set.open("data/cache.dets",
///   key_decoder: decode.string, value_decoder: decode.int)
/// ```
///
pub fn open(
  path: String,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Set(k, v), DetsError) {
  open_with(path, AutoRepair, key_decoder:, value_decoder:)
}

/// Open or create a DETS set table with a specific repair policy.
///
/// The repair policy controls what happens when the table file was not
/// closed cleanly, for example after an abnormal node shutdown:
///
/// - `AutoRepair`: Attempt repair if needed. This is the default for `open`.
/// - `ForceRepair`: Repair even if the file was closed properly.
/// - `NoRepair`: Return `NeedsRepair` if the file requires repair.
///
/// Make a backup before you repair a file with data you need to keep.
/// Repair does not guarantee recovery of all data.
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate.{ForceRepair}
/// let assert Ok(table) = set.open_with(path: "data/cache.dets",
///   repair: ForceRepair,
///   key_decoder: decode.string, value_decoder: decode.int)
/// ```
///
pub fn open_with(
  path path: String,
  repair repair: RepairPolicy,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Set(k, v), DetsError) {
  ffi_open_set(path, repair)
  |> result.map(fn(reference) { Set(reference:, key_decoder:, value_decoder:) })
}

/// Open a DETS set table with repair and access mode options.
///
/// Use `ReadOnly` to open a table for reading only. Write operations
/// on a read-only table will return `Error(AccessDenied(context))`.
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate.{AutoRepair, ReadOnly}
/// let assert Ok(table) = set.open_with_access(path: "data/cache.dets",
///   repair: AutoRepair, access: ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(value) = set.lookup(table, key: "key")
/// // set.insert(table, "key", "val") would return Error(AccessDenied(context))
/// ```
///
pub fn open_with_access(
  path path: String,
  repair repair: RepairPolicy,
  access access: AccessMode,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Set(k, v), DetsError) {
  ffi_open_set_with_access(path, repair, access)
  |> result.map(fn(reference) { Set(reference:, key_decoder:, value_decoder:) })
}

/// Close the table, flushing all pending writes to disk.
///
/// The table handle must not be used after closing.
pub fn close(table: Set(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.reference)
}

/// Flush pending writes to disk without closing the table.
///
/// By default, DETS saves the table after three minutes without table access.
/// Call `sync` and handle its result when you need to write pending updates
/// to disk before continuing.
pub fn sync(table: Set(k, v)) -> Result(Nil, DetsError) {
  ffi_sync(table.reference)
}

/// Use a table within a callback with repair and access mode options.
///
/// Select the repair policy and access mode as for `open_with_access`.
/// The callback must return a `Result`. `ReadOnly` requires an existing
/// file, and writes return `Error(AccessDenied(context))`. `NoRepair` returns
/// `Error(NeedsRepair(context))` if the file was not closed cleanly.
///
/// If opening fails, returns the open error without calling the callback.
/// Otherwise, runs the callback and attempts to close the table. If close
/// fails after a successful callback, returns the close error. If both fail,
/// returns the callback error. If the callback raises, attempts close before
/// re-raising the original exception.
///
/// Keep the table handle within the callback; do not use it after cleanup.
/// This cannot guarantee cleanup if the process is killed.
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate.{NoRepair, ReadOnly}
/// import slate/set
///
/// use table <- set.with_table(path: "data/cache.dets",
///   repair: NoRepair, access: ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// set.lookup(table, key: "key")
/// ```
///
pub fn with_table(
  path path: String,
  repair repair: RepairPolicy,
  access access: AccessMode,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
  callback callback: fn(Set(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open_with_access(path, repair, access, key_decoder:, value_decoder:) {
    Ok(table) -> ffi_with_close(table, callback, close)
    Error(error) -> Error(error)
  }
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up the value for a key.
///
/// Returns `Error(NotFound)` if the key does not exist.
/// Returns `Error(DecodeErrors(_))` if the stored value does not match the
/// expected type.
///
/// For bag and duplicate bag tables, `lookup` returns `Ok([])` for missing
/// keys instead of `Error(NotFound)`.
pub fn lookup(from table: Set(k, v), key key: k) -> Result(v, DetsError) {
  case ffi_lookup(table.reference, key) {
    Ok(dynamic_value) ->
      decode.run(dynamic_value, table.value_decoder)
      |> result.map_error(slate.DecodeErrors)
    Error(error) -> Error(error)
  }
}

/// Check if a key exists without returning the value.
pub fn member(of table: Set(k, v), key key: k) -> Result(Bool, DetsError) {
  ffi_member(table.reference, key)
}

/// Return all entries as a list in an unspecified order.
///
/// This loads the entire table into memory.
/// Returns `Error(DecodeErrors(_))` if any entry does not match the
/// expected types.
pub fn to_list(from table: Set(k, v)) -> Result(List(#(k, v)), DetsError) {
  case ffi_to_list(table.reference) {
    Ok(entries) ->
      internal.decode_entries(entries, table.key_decoder, table.value_decoder)
    Error(error) -> Error(error)
  }
}

/// Fold over all entries. Order is unspecified.
///
/// Returns `Error(DecodeErrors(_))` if any entry does not match the
/// expected types. The fold stops at the first decode error. If the callback
/// raises, the exception is re-raised.
pub fn fold(
  over table: Set(k, v),
  from initial: acc,
  with callback: fn(acc, k, v) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder =
    internal.tuple_decoder(table.key_decoder, table.value_decoder)
  let wrapper = fn(entry: Dynamic, accumulator_result: Result(acc, DetsError)) {
    case accumulator_result {
      Error(error) -> Error(error)
      Ok(accumulator) ->
        case decode.run(entry, entry_decoder) {
          Ok(#(key, value)) -> Ok(callback(accumulator, key, value))
          Error(errors) -> Error(slate.DecodeErrors(errors))
        }
    }
  }
  ffi_fold(table.reference, wrapper, Ok(initial))
  |> result.flatten
}

/// Call your callback once for each entry, in an unspecified order.
///
/// Pass the decoded entry as `Ok(#(key, value))`, or its decode errors as
/// `Error(decode_errors)`. The callback returns the next accumulator value.
/// Unlike `fold`, this function continues after a decode error.
///
/// The function returns `Ok(accumulator)` when it finishes. A table error,
/// such as `TableDoesNotExist`, makes the function return `Error(error)`.
/// If the callback raises an exception, that exception propagates to the caller.
///
/// ## Examples
///
/// Skip entries that fail to decode:
///
/// ```gleam
/// set.fold_results(table, [], fn(acc, entry) {
///   case entry {
///     Ok(#(key, value)) -> [#(key, value), ..acc]
///     Error(_) -> acc
///   }
/// })
/// ```
///
/// Collect decoded entries and decode errors separately:
///
/// ```gleam
/// set.fold_results(table, #([], []), fn(acc, entry) {
///   case entry {
///     Ok(#(key, value)) -> #([#(key, value), ..acc.0], acc.1)
///     Error(errors) -> #(acc.0, [errors, ..acc.1])
///   }
/// })
/// ```
pub fn fold_results(
  over table: Set(k, v),
  from initial: acc,
  with callback: fn(acc, Result(#(k, v), List(decode.DecodeError))) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder =
    internal.tuple_decoder(table.key_decoder, table.value_decoder)
  let wrapper = fn(entry: Dynamic, accumulator: acc) {
    let decoded = decode.run(entry, entry_decoder)
    callback(accumulator, decoded)
  }
  ffi_fold(table.reference, wrapper, initial)
}

/// Return the number of stored entries. Each entry is one key-value pair.
pub fn size(of table: Set(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.reference)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. If the key exists, replace its value.
pub fn insert(
  into table: Set(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert(table.reference, #(key, value))
}

/// Insert multiple key-value pairs.
pub fn insert_list(
  into table: Set(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.reference, entries)
}

/// Insert only if the key does not already exist.
///
/// Returns `Error(KeyAlreadyPresent)` if the key exists.
pub fn insert_new(
  into table: Set(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert_new(table.reference, #(key, value))
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete the entry with the given key.
///
/// Returns `Ok(Nil)` even if the key does not exist.
pub fn delete_key(from table: Set(k, v), key key: k) -> Result(Nil, DetsError) {
  ffi_delete_key(table.reference, key)
}

/// Delete a specific key-value pair from the table.
///
/// Unlike `delete_key`, this only removes the entry if both the key
/// and value match. For set tables, this acts as a conditional delete:
/// the entry is removed only when the stored value equals the given value.
pub fn delete_object(
  from table: Set(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_delete_object(table.reference, #(key, value))
}

/// Delete all entries and keep the table open.
pub fn delete_all(from table: Set(k, v)) -> Result(Nil, DetsError) {
  ffi_delete_all(table.reference)
}

// ── Counters ────────────────────────────────────────────────────────────

/// Atomically increment a counter value by the given amount.
///
/// The value associated with the key must be an integer. Returns the
/// new value after incrementing. The increment can be negative.
///
/// Returns `Error(TableError(slate.NotFound))` if the key does not exist,
/// `Error(CounterValueNotInteger)` if the stored value is not an integer,
/// or `Error(TableError(error))` for other DETS table failures.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = set.open("counters.dets",
///   key_decoder: decode.string, value_decoder: decode.int)
/// let assert Ok(Nil) = set.insert(table, "hits", 0)
/// let assert Ok(1) = set.update_counter(table, "hits", 1)
/// let assert Ok(3) = set.update_counter(table, "hits", 2)
/// ```
///
pub fn update_counter(
  in table: Set(k, Int),
  key key: k,
  increment amount: Int,
) -> Result(Int, UpdateCounterError) {
  ffi_update_counter(table.reference, key, amount)
  |> result.map_error(ffi_error_to_update_counter_error)
}

// ── Info ────────────────────────────────────────────────────────────────

/// Get the file size in bytes, entry count, and absolute path of an open table.
///
/// Returns `Error(TableDoesNotExist)` if the table is no longer open.
pub fn info(table: Set(k, v)) -> Result(slate.TableInfo, DetsError) {
  use file_size <- result.try(ffi_info_file_size(table.reference))
  use object_count <- result.try(ffi_info_size(table.reference))
  use file_path <- result.try(ffi_info_path(table.reference))
  Ok(slate.TableInfo(file_size:, object_count:, file_path:))
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "slate_dets_ffi", "open_set")
fn ffi_open_set(
  path: String,
  repair: RepairPolicy,
) -> Result(TableReference, DetsError)

@external(erlang, "slate_dets_ffi", "open_set_with_access")
fn ffi_open_set_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
) -> Result(TableReference, DetsError)

@external(erlang, "slate_dets_ffi", "close")
fn ffi_close(reference: TableReference) -> Result(Nil, DetsError)

@external(erlang, "slate_with_table_ffi", "with_close")
fn ffi_with_close(
  table: Set(k, v),
  callback: fn(Set(k, v)) -> Result(a, DetsError),
  close: fn(Set(k, v)) -> Result(Nil, DetsError),
) -> Result(a, DetsError)

@external(erlang, "slate_dets_ffi", "sync")
fn ffi_sync(reference: TableReference) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "insert")
fn ffi_insert(
  reference: TableReference,
  objects: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "insert")
fn ffi_insert_list(
  reference: TableReference,
  objects: List(#(k, v)),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "insert_new")
fn ffi_insert_new(
  reference: TableReference,
  objects: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "lookup")
fn ffi_lookup(reference: TableReference, key: k) -> Result(Dynamic, DetsError)

@external(erlang, "slate_dets_ffi", "member")
fn ffi_member(reference: TableReference, key: k) -> Result(Bool, DetsError)

@external(erlang, "slate_dets_ffi", "to_list")
fn ffi_to_list(reference: TableReference) -> Result(List(Dynamic), DetsError)

@external(erlang, "slate_dets_ffi", "fold")
fn ffi_fold(
  reference: TableReference,
  callback: fn(Dynamic, acc) -> acc,
  accumulator: acc,
) -> Result(acc, DetsError)

@external(erlang, "slate_dets_ffi", "info_size")
fn ffi_info_size(reference: TableReference) -> Result(Int, DetsError)

@external(erlang, "slate_dets_ffi", "info_file_size")
fn ffi_info_file_size(reference: TableReference) -> Result(Int, DetsError)

@external(erlang, "slate_dets_ffi", "info_path")
fn ffi_info_path(reference: TableReference) -> Result(String, DetsError)

@external(erlang, "slate_dets_ffi", "update_counter")
fn ffi_update_counter(
  reference: TableReference,
  key: k,
  increment: Int,
) -> Result(Int, UpdateCounterFfiError)

@external(erlang, "slate_dets_ffi", "delete_key")
fn ffi_delete_key(reference: TableReference, key: k) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "delete_object")
fn ffi_delete_object(
  reference: TableReference,
  object: #(k, v),
) -> Result(Nil, DetsError)

fn ffi_error_to_update_counter_error(
  error: UpdateCounterFfiError,
) -> UpdateCounterError {
  case error {
    FfiCounterValueNotInteger -> CounterValueNotInteger
    FfiTableError(error) -> TableError(error)
  }
}

@external(erlang, "slate_dets_ffi", "delete_all")
fn ffi_delete_all(reference: TableReference) -> Result(Nil, DetsError)
