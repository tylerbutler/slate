//// DETS bag tables: multiple distinct values per key.
////
//// Bag tables store multiple distinct values for the same key.
//// If a pair exists, `insert` returns `Ok(Nil)` without adding another copy.
//// Use `insert_new` when you need to detect duplicates.
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
//// let assert Ok(colors) = bag.lookup(table, "color")
//// // Contains "red" and "blue" in an unspecified order
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
/// The parent directory must exist. This function uses `AutoRepair` and
/// `ReadWrite`.
///
/// Reads use your decoders to check stored data. Opening a table does not
/// check all its entries.
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
/// on a read-only table will return `Error(AccessDenied(context))`.
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate.{AutoRepair, ReadOnly}
/// let assert Ok(table) = bag.open_with_access(path: "data/tags.dets",
///   repair: AutoRepair, access: ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(values) = bag.lookup(table, key: "key")
/// // bag.insert(table, "key", "val") would return Error(AccessDenied(context))
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
///
/// The table handle must not be used after closing.
pub fn close(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.reference)
}

/// Flush pending writes to disk without closing the table.
///
/// By default, DETS saves the table after three minutes without table access.
/// Call `sync` and handle its result when you need to write pending updates
/// to disk before continuing.
pub fn sync(table: Bag(k, v)) -> Result(Nil, DetsError) {
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
  callback callback: fn(Bag(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open_with_access(path, repair, access, key_decoder:, value_decoder:) {
    Ok(table) -> ffi_with_close(table, callback, close)
    Error(error) -> Error(error)
  }
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up all values for a key, in an unspecified order.
///
/// Returns `Ok([])` if the key does not exist. This differs from
/// `set.lookup`, which returns `Error(NotFound)` for missing keys.
/// Returns `Error(DecodeErrors(_))` if any stored value does not match the
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

/// Return all entries as a list in an unspecified order.
///
/// This loads the entire table into memory.
/// Returns `Error(DecodeErrors(_))` if any entry does not match the
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
/// Returns `Error(DecodeErrors(_))` if any entry does not match the
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
/// bag.fold_results(table, [], fn(acc, entry) {
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
  let wrapper = fn(entry: Dynamic, accumulator: acc) {
    let decoded = decode.run(entry, entry_decoder)
    callback(accumulator, decoded)
  }
  ffi_fold(table.reference, wrapper, initial)
}

/// Return the number of stored entries, not the number of distinct keys.
///
/// Each entry is one key-value pair.
pub fn size(of table: Bag(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.reference)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair.
///
/// If the pair exists, returns `Ok(Nil)` without adding another copy.
///
/// Multiple distinct values for the same key are stored separately.
pub fn insert(
  into table: Bag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert(table.reference, #(key, value))
}

/// Insert multiple key-value pairs.
///
/// Repeated pairs do not add extra copies.
pub fn insert_list(
  into table: Bag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.reference, entries)
}

/// Insert a key-value pair only if the exact pair does not already exist.
///
/// Returns `Error(KeyAlreadyPresent)` if the exact key-value pair is
/// already in the table. Use `insert` when you do not need duplicate
/// detection.
///
/// Concurrent calls can both return `Ok(Nil)` for the same pair.
/// The table still stores one copy. To ensure only one caller reports a new
/// insertion, serialize writes through an owner process.
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
/// Returns `Ok(Nil)` even if the key does not exist.
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

/// Delete all entries and keep the table open.
pub fn delete_all(from table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_delete_all(table.reference)
}

// ── Info ────────────────────────────────────────────────────────────────

/// Get the file size in bytes, entry count, and absolute path of an open table.
///
/// Returns `Error(TableDoesNotExist)` if the table is no longer open.
pub fn info(table: Bag(k, v)) -> Result(slate.TableInfo, DetsError) {
  use file_size <- result.try(ffi_info_file_size(table.reference))
  use object_count <- result.try(ffi_info_size(table.reference))
  use file_path <- result.try(ffi_info_path(table.reference))
  Ok(slate.TableInfo(file_size:, object_count:, file_path:))
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
  accumulator: acc,
) -> Result(acc, DetsError)

@external(erlang, "slate_dets_ffi", "info_size")
fn ffi_info_size(reference: TableReference) -> Result(Int, DetsError)

@external(erlang, "slate_dets_ffi", "info_file_size")
fn ffi_info_file_size(reference: TableReference) -> Result(Int, DetsError)

@external(erlang, "slate_dets_ffi", "info_path")
fn ffi_info_path(reference: TableReference) -> Result(String, DetsError)

@external(erlang, "slate_dets_ffi", "delete_key")
fn ffi_delete_key(reference: TableReference, key: k) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "delete_object")
fn ffi_delete_object(
  reference: TableReference,
  object: #(k, v),
) -> Result(Nil, DetsError)

@external(erlang, "slate_dets_ffi", "delete_all")
fn ffi_delete_all(reference: TableReference) -> Result(Nil, DetsError)
