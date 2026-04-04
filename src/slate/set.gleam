/// DETS set tables — one value per key.
///
/// Set tables store key-value pairs where each key maps to exactly one value.
/// Inserting with an existing key overwrites the previous value.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate/set
///
/// let assert Ok(table) = set.open("users.dets",
///   key_decoder: decode.string, value_decoder: decode.int)
/// let assert Ok(Nil) = set.insert(table, "alice", 42)
/// let assert Ok(42) = set.lookup(table, "alice")
/// let assert Ok(Nil) = set.close(table)
/// ```
///
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
  Set(ref: TableRef, key_decoder: Decoder(k), value_decoder: Decoder(v))
}

/// Internal reference to the DETS table (Erlang atom).
type TableRef

type UpdateCounterFfiError {
  FfiCounterValueNotInteger
  FfiTableError(DetsError)
}

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open or create a DETS set table at the given file path.
///
/// Decoders are used to validate data read from disk, ensuring type safety
/// even when opening files created by other code or previous runs.
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

/// Open or create a DETS set table with repair options.
pub fn open_with(
  path: String,
  repair: RepairPolicy,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Set(k, v), DetsError) {
  ffi_open_set(path, repair)
  |> result.map(fn(ref) { Set(ref:, key_decoder:, value_decoder:) })
}

/// Open a DETS set table with repair and access mode options.
///
/// Use `ReadOnly` to open a table for reading only. Write operations
/// on a read-only table will return `Error(AccessDenied)`.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = set.open_with_access(path, AutoRepair, ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(val) = set.lookup(table, key: "key")
/// // set.insert(table, "key", "val") would return Error(AccessDenied)
/// ```
///
pub fn open_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Set(k, v), DetsError) {
  ffi_open_set_with_access(path, repair, access)
  |> result.map(fn(ref) { Set(ref:, key_decoder:, value_decoder:) })
}

/// Close the table, flushing all pending writes to disk.
///
/// The table handle must not be used after closing.
pub fn close(table: Set(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.ref)
}

/// Flush pending writes to disk without closing the table.
pub fn sync(table: Set(k, v)) -> Result(Nil, DetsError) {
  ffi_sync(table.ref)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// This is the recommended way to use DETS tables for short-lived operations.
///
/// ```gleam
/// import gleam/dynamic/decode
/// use table <- set.with_table("data/cache.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// set.insert(table, "key", "value")
/// ```
///
pub fn with_table(
  path: String,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
  fun fun: fn(Set(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open(path, key_decoder:, value_decoder:) {
    Ok(table) -> ffi_with_close(table, fun, close)
    Error(err) -> Error(err)
  }
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up the value for a key.
///
/// Returns `Error(NotFound)` if the key does not exist.
/// Returns `Error(DecodeErrors(_))` if the stored value doesn't match the
/// expected type.
pub fn lookup(from table: Set(k, v), key key: k) -> Result(v, DetsError) {
  case ffi_lookup(table.ref, key) {
    Ok(dynamic_value) ->
      decode.run(dynamic_value, table.value_decoder)
      |> result.map_error(slate.DecodeErrors)
    Error(err) -> Error(err)
  }
}

/// Check if a key exists without returning the value.
pub fn member(of table: Set(k, v), key key: k) -> Result(Bool, DetsError) {
  ffi_member(table.ref, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types.
pub fn to_list(from table: Set(k, v)) -> Result(List(#(k, v)), DetsError) {
  case ffi_to_list(table.ref) {
    Ok(entries) ->
      internal.decode_entries(entries, table.key_decoder, table.value_decoder)
    Error(err) -> Error(err)
  }
}

/// Fold over all entries. Order is unspecified.
///
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types. The fold stops at the first decode error.
pub fn fold(
  over table: Set(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder =
    internal.tuple_decoder(table.key_decoder, table.value_decoder)
  let wrapper = fn(entry: Dynamic, acc_result: Result(acc, DetsError)) {
    case acc_result {
      Error(err) -> Error(err)
      Ok(acc) ->
        case decode.run(entry, entry_decoder) {
          Ok(#(k, v)) -> Ok(fun(acc, k, v))
          Error(errors) -> Error(slate.DecodeErrors(errors))
        }
    }
  }
  ffi_fold(table.ref, wrapper, Ok(initial))
  |> result.flatten
}

/// Fold over all entries, passing decode results to the callback.
///
/// Unlike `fold`, decode failures do not abort the traversal. Each entry
/// is presented to the callback as `Ok(#(key, value))` on success or
/// `Error(decode_errors)` on failure, letting the caller decide how to
/// handle bad records.
///
/// DETS-level errors (e.g., the table does not exist) still fail the
/// entire operation via the outer `Result`.
///
/// ## Examples
///
/// Skip entries that fail to decode:
///
/// ```gleam
/// set.fold_results(table, [], fn(acc, entry) {
///   case entry {
///     Ok(#(k, v)) -> [#(k, v), ..acc]
///     Error(_) -> acc
///   }
/// })
/// ```
///
/// Partition into successes and failures:
///
/// ```gleam
/// set.fold_results(table, #([], []), fn(acc, entry) {
///   case entry {
///     Ok(#(k, v)) -> #([#(k, v), ..acc.0], acc.1)
///     Error(errs) -> #(acc.0, [errs, ..acc.1])
///   }
/// })
/// ```
pub fn fold_results(
  over table: Set(k, v),
  from initial: acc,
  with fun: fn(acc, Result(#(k, v), List(decode.DecodeError))) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder =
    internal.tuple_decoder(table.key_decoder, table.value_decoder)
  let wrapper = fn(entry: Dynamic, acc: acc) {
    let decoded = decode.run(entry, entry_decoder)
    fun(acc, decoded)
  }
  ffi_fold(table.ref, wrapper, initial)
}

/// Return the number of objects stored.
pub fn size(of table: Set(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.ref)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Overwrites if key exists.
pub fn insert(
  into table: Set(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert(table.ref, #(key, value))
}

/// Insert multiple key-value pairs.
pub fn insert_list(
  into table: Set(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.ref, entries)
}

/// Insert only if the key does not already exist.
///
/// Returns `Error(KeyAlreadyPresent)` if the key exists.
pub fn insert_new(
  into table: Set(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert_new(table.ref, #(key, value))
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete the entry with the given key.
pub fn delete_key(from table: Set(k, v), key key: k) -> Result(Nil, DetsError) {
  ffi_delete_key(table.ref, key)
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
  ffi_delete_object(table.ref, #(key, value))
}

/// Delete all objects in the table (keeps the table open).
pub fn delete_all(from table: Set(k, v)) -> Result(Nil, DetsError) {
  ffi_delete_all(table.ref)
}

// ── Counters ────────────────────────────────────────────────────────────

/// Atomically increment a counter value by the given amount.
///
/// The value associated with the key must be an integer. Returns the
/// new value after incrementing. The increment can be negative.
///
/// Returns `Error(TableError(slate.NotFound))` if the key doesn't exist,
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
  ffi_update_counter(table.ref, key, amount)
  |> result.map_error(update_counter_error_from_ffi)
}

// ── Info ────────────────────────────────────────────────────────────────

/// Get information about an open table.
pub fn info(table: Set(k, v)) -> Result(slate.TableInfo, DetsError) {
  case ffi_info_file_size(table.ref), ffi_info_size(table.ref) {
    Ok(file_size), Ok(object_count) ->
      Ok(slate.TableInfo(
        file_size: file_size,
        object_count: object_count,
        kind: slate.Set,
      ))
    Error(err), _ -> Error(err)
    _, Error(err) -> Error(err)
  }
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "dets_ffi", "open_set")
fn ffi_open_set(
  path: String,
  repair: RepairPolicy,
) -> Result(TableRef, DetsError)

@external(erlang, "dets_ffi", "open_set_with_access")
fn ffi_open_set_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
) -> Result(TableRef, DetsError)

@external(erlang, "dets_ffi", "close")
fn ffi_close(ref: TableRef) -> Result(Nil, DetsError)

@external(erlang, "with_table_ffi", "with_close")
fn ffi_with_close(
  table: Set(k, v),
  fun: fn(Set(k, v)) -> Result(a, DetsError),
  close: fn(Set(k, v)) -> Result(Nil, DetsError),
) -> Result(a, DetsError)

@external(erlang, "dets_ffi", "sync")
fn ffi_sync(ref: TableRef) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "insert")
fn ffi_insert(ref: TableRef, objects: #(k, v)) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "insert")
fn ffi_insert_list(
  ref: TableRef,
  objects: List(#(k, v)),
) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "insert_new")
fn ffi_insert_new(ref: TableRef, objects: #(k, v)) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "lookup")
fn ffi_lookup(ref: TableRef, key: k) -> Result(Dynamic, DetsError)

@external(erlang, "dets_ffi", "member")
fn ffi_member(ref: TableRef, key: k) -> Result(Bool, DetsError)

@external(erlang, "dets_ffi", "to_list")
fn ffi_to_list(ref: TableRef) -> Result(List(Dynamic), DetsError)

@external(erlang, "dets_ffi", "fold")
fn ffi_fold(
  ref: TableRef,
  fun: fn(Dynamic, acc) -> acc,
  acc: acc,
) -> Result(acc, DetsError)

@external(erlang, "dets_ffi", "info_size")
fn ffi_info_size(ref: TableRef) -> Result(Int, DetsError)

@external(erlang, "dets_ffi", "info_file_size")
fn ffi_info_file_size(ref: TableRef) -> Result(Int, DetsError)

@external(erlang, "dets_ffi", "update_counter")
fn ffi_update_counter(
  ref: TableRef,
  key: k,
  increment: Int,
) -> Result(Int, UpdateCounterFfiError)

@external(erlang, "dets_ffi", "delete_key")
fn ffi_delete_key(ref: TableRef, key: k) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "delete_object")
fn ffi_delete_object(ref: TableRef, object: #(k, v)) -> Result(Nil, DetsError)

fn update_counter_error_from_ffi(
  error: UpdateCounterFfiError,
) -> UpdateCounterError {
  case error {
    FfiCounterValueNotInteger -> CounterValueNotInteger
    FfiTableError(error) -> TableError(error)
  }
}

@external(erlang, "dets_ffi", "delete_all")
fn ffi_delete_all(ref: TableRef) -> Result(Nil, DetsError)
