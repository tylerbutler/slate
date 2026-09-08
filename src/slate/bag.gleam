//// DETS bag tables — multiple distinct values per key.
////
//// Bag tables allow storing multiple values for the same key. Duplicate
//// key-value pairs are silently ignored by `insert`. Use `insert_new`
//// when you need to detect duplicates.
////
//// ## Example
////
//// ```gleam
//// import gleam/dynamic/decode
//// import slate/bag
////
//// let assert Ok(table) = bag.open("tags.dets",
////   key_decoder: decode.string, value_decoder: decode.string)
//// let assert Ok(Nil) = bag.insert(table, "color", "red")
//// let assert Ok(Nil) = bag.insert(table, "color", "blue")
//// let assert Ok(["red", "blue"]) = bag.lookup(table, "color")
//// let assert Ok(Nil) = bag.close(table)
//// ```
////

import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/list
import gleam/result
import slate.{type AccessMode, type DetsError, type RepairPolicy, AutoRepair}
import slate/internal

/// An open DETS bag table with typed keys and values.
pub opaque type Bag(k, v) {
  Bag(
    reference: TableReference,
    key_decoder: Decoder(k),
    value_decoder: Decoder(v),
  )
}

/// Internal reference to the DETS table (Erlang atom).
type TableReference

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open or create a DETS bag table at the given file path.
///
/// Decoders are used to validate data read from disk, ensuring type safety
/// even when opening files created by other code or previous runs.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = bag.open("data/tags.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// ```
///
pub fn open(
  path: String,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Bag(k, v), DetsError) {
  open_with(path, AutoRepair, key_decoder:, value_decoder:)
}

/// Open or create a DETS bag table with a specific repair policy.
///
/// The repair policy controls what happens when the table file was not
/// closed cleanly (e.g., after a crash):
///
/// - `AutoRepair` — silently repair the file if needed (default for `open`)
/// - `ForceRepair` — repair even if the file appears clean
/// - `NoRepair` — return an error instead of repairing
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate.{ForceRepair}
/// let assert Ok(table) = bag.open_with(path: "data/tags.dets",
///   repair: ForceRepair,
///   key_decoder: decode.string, value_decoder: decode.string)
/// ```
///
pub fn open_with(
  path path: String,
  repair repair: RepairPolicy,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Bag(k, v), DetsError) {
  ffi_open_bag(path, repair)
  |> result.map(fn(reference) { Bag(reference:, key_decoder:, value_decoder:) })
}

/// Open a DETS bag table with repair and access mode options.
///
/// Use `ReadOnly` to open a table for reading only. Write operations
/// on a read-only table will return `Error(AccessDenied)`.
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate.{AutoRepair, ReadOnly}
/// let assert Ok(table) = bag.open_with_access(path: "data/tags.dets",
///   repair: AutoRepair, access: ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(values) = bag.lookup(table, key: "key")
/// // bag.insert(table, "key", "val") would return Error(AccessDenied)
/// ```
///
pub fn open_with_access(
  path path: String,
  repair repair: RepairPolicy,
  access access: AccessMode,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(Bag(k, v), DetsError) {
  ffi_open_bag_with_access(path, repair, access)
  |> result.map(fn(reference) { Bag(reference:, key_decoder:, value_decoder:) })
}

/// Close the table, flushing all pending writes to disk.
pub fn close(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.reference)
}

/// Flush pending writes to disk without closing the table.
///
/// DETS auto-syncs periodically, so this is only needed when you require
/// a durability guarantee at a specific point (e.g., after a critical write).
pub fn sync(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_sync(table.reference)
}

/// Use a table within a callback with repair and access mode options.
///
/// Pass `AutoRepair` and `ReadWrite` to keep the behavior of slate 1.x.
/// Uses the same options as `open_with_access`. `ReadOnly` requires an existing
/// file, and writes return `Error(AccessDenied)`. `NoRepair` returns
/// `Error(NeedsRepair)` if the file was not closed cleanly.
///
/// If opening fails, returns the open error without calling the callback.
/// Otherwise, closes the table before returning the callback result. If close
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
/// import slate/bag
///
/// use table <- bag.with_table(path: "data/tags.dets",
///   repair: NoRepair, access: ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// bag.lookup(table, key: "color")
/// ```
///
pub fn with_table(
  path path: String,
  repair repair: RepairPolicy,
  access access: AccessMode,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
  fun callback: fn(Bag(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open_with_access(path, repair, access, key_decoder:, value_decoder:) {
    Ok(table) -> ffi_with_close(table, callback, close)
    Error(error) -> Error(error)
  }
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up all values for a key.
///
/// Returns `Ok([])` if the key does not exist. This differs from
/// `set.lookup`, which returns `Error(NotFound)` for missing keys.
/// Returns `Error(DecodeErrors(_))` if any stored value doesn't match the
/// expected type.
pub fn lookup(from table: Bag(k, v), key key: k) -> Result(List(v), DetsError) {
  case ffi_lookup_all(table.reference, key) {
    Ok(dynamic_values) ->
      list.try_map(dynamic_values, fn(dynamic_value) {
        decode.run(dynamic_value, table.value_decoder)
        |> result.map_error(slate.DecodeErrors)
      })
    Error(error) -> Error(error)
  }
}

/// Check if a key exists without returning the values.
pub fn member(of table: Bag(k, v), key key: k) -> Result(Bool, DetsError) {
  ffi_member(table.reference, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types.
pub fn to_list(from table: Bag(k, v)) -> Result(List(#(k, v)), DetsError) {
  case ffi_to_list(table.reference) {
    Ok(entries) ->
      internal.decode_entries(entries, table.key_decoder, table.value_decoder)
    Error(error) -> Error(error)
  }
}

/// Fold over all entries. Order is unspecified.
///
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types. The fold stops at the first decode error. If the callback
/// raises, the exception is re-raised.
pub fn fold(
  over table: Bag(k, v),
  from initial: acc,
  with callback: fn(acc, k, v) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder =
    internal.tuple_decoder(table.key_decoder, table.value_decoder)
  let wrapper = fn(entry: Dynamic, accumulator_result: Result(acc, DetsError)) {
    case accumulator_result {
      Error(error) -> Error(error)
      Ok(acc) ->
        case decode.run(entry, entry_decoder) {
          Ok(#(key, value)) -> Ok(callback(acc, key, value))
          Error(errors) -> Error(slate.DecodeErrors(errors))
        }
    }
  }
  ffi_fold(table.reference, wrapper, Ok(initial))
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
/// entire operation via the outer `Result`. If the callback raises, the
/// exception is re-raised.
///
/// ## Examples
///
/// Skip entries that fail to decode:
///
/// ```gleam
/// bag.fold_results(table, [], fn(acc, entry) {
///   case entry {
///     Ok(#(key, value)) -> [#(key, value), ..acc]
///     Error(_) -> acc
///   }
/// })
/// ```
///
/// Partition into successes and failures:
///
/// ```gleam
/// bag.fold_results(table, #([], []), fn(acc, entry) {
///   case entry {
///     Ok(#(key, value)) -> #([#(key, value), ..acc.0], acc.1)
///     Error(errors) -> #(acc.0, [errors, ..acc.1])
///   }
/// })
/// ```
pub fn fold_results(
  over table: Bag(k, v),
  from initial: acc,
  with callback: fn(acc, Result(#(k, v), List(decode.DecodeError))) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder =
    internal.tuple_decoder(table.key_decoder, table.value_decoder)
  let wrapper = fn(entry: Dynamic, acc: acc) {
    let decoded = decode.run(entry, entry_decoder)
    callback(acc, decoded)
  }
  ffi_fold(table.reference, wrapper, initial)
}

/// Return the number of objects stored.
pub fn size(of table: Bag(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.reference)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. If the exact pair already exists, this is a
/// no-op (the duplicate is silently ignored).
///
/// Multiple distinct values for the same key are stored separately.
pub fn insert(
  into table: Bag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert(table.reference, #(key, value))
}

/// Insert multiple key-value pairs. Duplicate pairs already in the table
/// are silently ignored.
pub fn insert_list(
  into table: Bag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.reference, entries)
}

/// Insert a key-value pair only if the exact pair does not already exist.
///
/// Returns `Error(KeyAlreadyPresent)` if the exact key-value pair is
/// already in the table. Use `insert` when you don't need duplicate
/// detection.
///
/// Under shared concurrent access this check is best-effort rather than
/// atomic, because DETS does not provide an exact-object `insert_new`
/// operation for bag tables. If you need strict duplicate exclusion across
/// writers, serialize writes through an owner process.
pub fn insert_new(
  into table: Bag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert_new_object(table.reference, #(key, value))
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
///
/// This operation is idempotent — deleting a key that does not exist
/// succeeds with `Ok(Nil)`.
pub fn delete_key(from table: Bag(k, v), key key: k) -> Result(Nil, DetsError) {
  ffi_delete_key(table.reference, key)
}

/// Delete a specific key-value pair from the table.
///
/// Only the exact matching pair is removed. Other values for the same
/// key are preserved. This is the primary way to remove individual
/// values from a bag without affecting other entries for the same key.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = bag.open("tags.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(Nil) = bag.insert(table, "color", "red")
/// let assert Ok(Nil) = bag.insert(table, "color", "blue")
/// let assert Ok(Nil) = bag.delete_object(table, "color", "red")
/// let assert Ok(["blue"]) = bag.lookup(table, "color")
/// ```
///
pub fn delete_object(
  from table: Bag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_delete_object(table.reference, #(key, value))
}

/// Delete all objects in the table (keeps the table open).
pub fn delete_all(from table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_delete_all(table.reference)
}

// ── Info ────────────────────────────────────────────────────────────────

/// Get information about an open table.
pub fn info(table: Bag(k, v)) -> Result(slate.TableInfo, DetsError) {
  use file_size <- result.try(ffi_info_file_size(table.reference))
  use object_count <- result.try(ffi_info_size(table.reference))
  Ok(slate.TableInfo(file_size:, object_count:))
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "slate_dets_ffi", "open_bag")
fn ffi_open_bag(
  path: String,
  repair: RepairPolicy,
) -> Result(TableReference, DetsError)

@external(erlang, "slate_dets_ffi", "open_bag_with_access")
fn ffi_open_bag_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
) -> Result(TableReference, DetsError)

@external(erlang, "slate_dets_ffi", "close")
fn ffi_close(reference: TableReference) -> Result(Nil, DetsError)

@external(erlang, "slate_with_table_ffi", "with_close")
fn ffi_with_close(
  table: Bag(k, v),
  callback: fn(Bag(k, v)) -> Result(a, DetsError),
  close: fn(Bag(k, v)) -> Result(Nil, DetsError),
) -> Result(a, DetsError)

@external(erlang, "slate_dets_ffi", "sync")
fn ffi_sync(reference: TableReference) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "insert")
fn ffi_insert(
  reference: TableReference,
  objects: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "insert_new_object")
fn ffi_insert_new_object(
  reference: TableReference,
  objects: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "insert")
fn ffi_insert_list(
  reference: TableReference,
  objects: List(#(k, v)),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "lookup_all")
fn ffi_lookup_all(
  reference: TableReference,
  key: k,
) -> Result(List(Dynamic), DetsError)

@external(erlang, "slate_dets_ffi", "member")
fn ffi_member(reference: TableReference, key: k) -> Result(Bool, DetsError)

@external(erlang, "slate_dets_ffi", "to_list")
fn ffi_to_list(reference: TableReference) -> Result(List(Dynamic), DetsError)

@external(erlang, "slate_dets_ffi", "fold")
fn ffi_fold(
  reference: TableReference,
  callback: fn(Dynamic, acc) -> acc,
  acc: acc,
) -> Result(acc, DetsError)

@external(erlang, "slate_dets_ffi", "info_size")
fn ffi_info_size(reference: TableReference) -> Result(Int, DetsError)

@external(erlang, "slate_dets_ffi", "info_file_size")
fn ffi_info_file_size(reference: TableReference) -> Result(Int, DetsError)

@external(erlang, "slate_dets_ffi", "delete_key")
fn ffi_delete_key(reference: TableReference, key: k) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "delete_object")
fn ffi_delete_object(
  reference: TableReference,
  object: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "delete_all")
fn ffi_delete_all(reference: TableReference) -> Result(Nil, DetsError)
