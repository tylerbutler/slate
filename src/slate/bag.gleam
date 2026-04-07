/// DETS bag tables — multiple distinct values per key.
///
/// Bag tables allow storing multiple values for the same key. Duplicate
/// key-value pairs are silently ignored by `insert`. Use `insert_new`
/// when you need to detect duplicates.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate/bag
///
/// let assert Ok(table) = bag.open("tags.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(Nil) = bag.insert(table, "color", "red")
/// let assert Ok(Nil) = bag.insert(table, "color", "blue")
/// let assert Ok(["red", "blue"]) = bag.lookup(table, "color")
/// let assert Ok(Nil) = bag.close(table)
/// ```
///
import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/list
import gleam/result
import slate.{type AccessMode, type DetsError, type RepairPolicy, AutoRepair}
import slate/internal

/// An open DETS bag table with typed keys and values.
pub opaque type Bag(k, v) {
  Bag(ref: TableRef, key_decoder: Decoder(k), value_decoder: Decoder(v))
}

/// Internal reference to the DETS table (Erlang atom).
type TableRef

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
  |> result.map(fn(ref) { Bag(ref:, key_decoder:, value_decoder:) })
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
/// let assert Ok(vals) = bag.lookup(table, key: "key")
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
  |> result.map(fn(ref) { Bag(ref:, key_decoder:, value_decoder:) })
}

/// Close the table, flushing all pending writes to disk.
pub fn close(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.ref)
}

/// Flush pending writes to disk without closing the table.
///
/// DETS auto-syncs periodically, so this is only needed when you require
/// a durability guarantee at a specific point (e.g., after a critical write).
pub fn sync(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_sync(table.ref)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// This is the recommended way to use DETS tables for short-lived operations.
/// Opens with `AutoRepair` and `ReadWrite` access; use `open_with_access`
/// and manual `close` if you need different settings.
///
/// If both the callback and close fail, the callback error is returned.
/// If the callback raises an exception, close is attempted before re-raising.
///
/// ```gleam
/// import gleam/dynamic/decode
/// use table <- bag.with_table("data/tags.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// bag.insert(table, "color", "red")
/// ```
///
pub fn with_table(
  path: String,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
  fun fun: fn(Bag(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open(path, key_decoder:, value_decoder:) {
    Ok(table) -> ffi_with_close(table, fun, close)
    Error(err) -> Error(err)
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
  case ffi_lookup_all(table.ref, key) {
    Ok(dynamic_values) ->
      list.try_map(dynamic_values, fn(dv) {
        decode.run(dv, table.value_decoder)
        |> result.map_error(slate.DecodeErrors)
      })
    Error(err) -> Error(err)
  }
}

/// Check if a key exists without returning the values.
pub fn member(of table: Bag(k, v), key key: k) -> Result(Bool, DetsError) {
  ffi_member(table.ref, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types.
pub fn to_list(from table: Bag(k, v)) -> Result(List(#(k, v)), DetsError) {
  case ffi_to_list(table.ref) {
    Ok(entries) ->
      internal.decode_entries(entries, table.key_decoder, table.value_decoder)
    Error(err) -> Error(err)
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
///     Ok(#(k, v)) -> [#(k, v), ..acc]
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
///     Ok(#(k, v)) -> #([#(k, v), ..acc.0], acc.1)
///     Error(errs) -> #(acc.0, [errs, ..acc.1])
///   }
/// })
/// ```
pub fn fold_results(
  over table: Bag(k, v),
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
pub fn size(of table: Bag(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.ref)
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
  ffi_insert(table.ref, #(key, value))
}

/// Insert multiple key-value pairs. Duplicate pairs already in the table
/// are silently ignored.
pub fn insert_list(
  into table: Bag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.ref, entries)
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
  ffi_insert_new_object(table.ref, #(key, value))
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
///
/// This operation is idempotent — deleting a key that does not exist
/// succeeds with `Ok(Nil)`.
pub fn delete_key(from table: Bag(k, v), key key: k) -> Result(Nil, DetsError) {
  ffi_delete_key(table.ref, key)
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
  ffi_delete_object(table.ref, #(key, value))
}

/// Delete all objects in the table (keeps the table open).
pub fn delete_all(from table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_delete_all(table.ref)
}

// ── Info ────────────────────────────────────────────────────────────────

/// Get information about an open table.
pub fn info(table: Bag(k, v)) -> Result(slate.TableInfo, DetsError) {
  case ffi_info_file_size(table.ref), ffi_info_size(table.ref) {
    Ok(file_size), Ok(object_count) ->
      Ok(slate.TableInfo(file_size:, object_count:))
    Error(err), _ -> Error(err)
    _, Error(err) -> Error(err)
  }
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "dets_ffi", "open_bag")
fn ffi_open_bag(
  path: String,
  repair: RepairPolicy,
) -> Result(TableRef, DetsError)

@external(erlang, "dets_ffi", "open_bag_with_access")
fn ffi_open_bag_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
) -> Result(TableRef, DetsError)

@external(erlang, "dets_ffi", "close")
fn ffi_close(ref: TableRef) -> Result(Nil, DetsError)

@external(erlang, "with_table_ffi", "with_close")
fn ffi_with_close(
  table: Bag(k, v),
  fun: fn(Bag(k, v)) -> Result(a, DetsError),
  close: fn(Bag(k, v)) -> Result(Nil, DetsError),
) -> Result(a, DetsError)

@external(erlang, "dets_ffi", "sync")
fn ffi_sync(ref: TableRef) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "insert")
fn ffi_insert(ref: TableRef, objects: #(k, v)) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "insert_new_object")
fn ffi_insert_new_object(
  ref: TableRef,
  objects: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "insert")
fn ffi_insert_list(
  ref: TableRef,
  objects: List(#(k, v)),
) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "lookup_all")
fn ffi_lookup_all(ref: TableRef, key: k) -> Result(List(Dynamic), DetsError)

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

@external(erlang, "dets_ffi", "delete_key")
fn ffi_delete_key(ref: TableRef, key: k) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "delete_object")
fn ffi_delete_object(ref: TableRef, object: #(k, v)) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "delete_all")
fn ffi_delete_all(ref: TableRef) -> Result(Nil, DetsError)
