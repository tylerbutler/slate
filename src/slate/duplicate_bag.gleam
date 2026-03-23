/// DETS duplicate bag tables — multiple values per key, duplicates allowed.
///
/// Duplicate bag tables are like bag tables but allow storing identical
/// key-value pairs multiple times.
///
/// ## Example
///
/// ```gleam
/// import gleam/dynamic/decode
/// import slate/duplicate_bag
///
/// let assert Ok(table) = duplicate_bag.open("events.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_a")
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "button_a")
/// let assert Ok(["button_a", "button_a"]) =
///   duplicate_bag.lookup(table, "click")
/// let assert Ok(Nil) = duplicate_bag.close(table)
/// ```
///
import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/list
import gleam/result
import slate.{type AccessMode, type DetsError, type RepairPolicy, AutoRepair}

/// An open DETS duplicate bag table with typed keys and values.
pub opaque type DuplicateBag(k, v) {
  DuplicateBag(
    ref: TableRef,
    key_decoder: Decoder(k),
    value_decoder: Decoder(v),
  )
}

/// Internal reference to the DETS table (Erlang atom).
type TableRef

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open or create a DETS duplicate bag table at the given file path.
///
/// Decoders are used to validate data read from disk, ensuring type safety
/// even when opening files created by other code or previous runs.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = duplicate_bag.open("data/events.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// ```
///
pub fn open(
  path: String,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(DuplicateBag(k, v), DetsError) {
  open_with(path, AutoRepair, key_decoder:, value_decoder:)
}

/// Open or create a DETS duplicate bag table with repair options.
pub fn open_with(
  path: String,
  repair: RepairPolicy,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(DuplicateBag(k, v), DetsError) {
  ffi_open_duplicate_bag(path, repair)
  |> result.map(fn(ref) { DuplicateBag(ref:, key_decoder:, value_decoder:) })
}

/// Open a DETS duplicate bag table with repair and access mode options.
///
/// Use `ReadOnly` to open a table for reading only. Write operations
/// on a read-only table will return `Error(AccessDenied)`.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = duplicate_bag.open_with_access(path, AutoRepair, ReadOnly,
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(vals) = duplicate_bag.lookup(table, key: "key")
/// // duplicate_bag.insert(table, "key", "val") would return Error(AccessDenied)
/// ```
///
pub fn open_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
) -> Result(DuplicateBag(k, v), DetsError) {
  ffi_open_duplicate_bag_with_access(path, repair, access)
  |> result.map(fn(ref) { DuplicateBag(ref:, key_decoder:, value_decoder:) })
}

/// Close the table, flushing all pending writes to disk.
pub fn close(table: DuplicateBag(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.ref)
}

/// Flush pending writes to disk without closing the table.
pub fn sync(table: DuplicateBag(k, v)) -> Result(Nil, DetsError) {
  ffi_sync(table.ref)
}

/// Use a table within a callback, ensuring it is closed afterward.
///
/// This is the recommended way to use DETS tables for short-lived operations.
///
/// ```gleam
/// import gleam/dynamic/decode
/// use table <- duplicate_bag.with_table("data/events.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// duplicate_bag.insert(table, "click", "button_a")
/// ```
///
pub fn with_table(
  path: String,
  key_decoder key_decoder: Decoder(k),
  value_decoder value_decoder: Decoder(v),
  fun fun: fn(DuplicateBag(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open(path, key_decoder:, value_decoder:) {
    Ok(table) -> ffi_with_close(table, fun, close)
    Error(err) -> Error(err)
  }
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up all values for a key. Returns an empty list if key not found.
///
/// Returns `Error(DecodeErrors(_))` if any stored value doesn't match the
/// expected type.
pub fn lookup(
  from table: DuplicateBag(k, v),
  key key: k,
) -> Result(List(v), DetsError) {
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
pub fn member(
  of table: DuplicateBag(k, v),
  key key: k,
) -> Result(Bool, DetsError) {
  ffi_member(table.ref, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types.
pub fn to_list(
  from table: DuplicateBag(k, v),
) -> Result(List(#(k, v)), DetsError) {
  case ffi_to_list(table.ref) {
    Ok(entries) ->
      decode_entries(entries, table.key_decoder, table.value_decoder)
    Error(err) -> Error(err)
  }
}

/// Fold over all entries. Order is unspecified.
///
/// Returns `Error(DecodeErrors(_))` if any entry doesn't match the
/// expected types. The fold stops at the first decode error.
pub fn fold(
  over table: DuplicateBag(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, DetsError) {
  let entry_decoder = tuple_decoder(table.key_decoder, table.value_decoder)
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

/// Return the number of objects stored.
pub fn size(of table: DuplicateBag(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.ref)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Duplicates are stored separately.
pub fn insert(
  into table: DuplicateBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert(table.ref, #(key, value))
}

/// Insert multiple key-value pairs.
pub fn insert_list(
  into table: DuplicateBag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.ref, entries)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
pub fn delete_key(
  from table: DuplicateBag(k, v),
  key key: k,
) -> Result(Nil, DetsError) {
  ffi_delete_key(table.ref, key)
}

/// Delete all occurrences of a specific key-value pair from the table.
///
/// In a duplicate bag, this removes every copy of the exact pair.
/// Other values (or different duplicates) for the same key are preserved.
///
/// ```gleam
/// import gleam/dynamic/decode
/// let assert Ok(table) = duplicate_bag.open("events.dets",
///   key_decoder: decode.string, value_decoder: decode.string)
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_a")
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_a")
/// let assert Ok(Nil) = duplicate_bag.insert(table, "click", "btn_b")
/// let assert Ok(Nil) = duplicate_bag.delete_object(table, "click", "btn_a")
/// // Only "btn_b" remains
/// ```
///
pub fn delete_object(
  from table: DuplicateBag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_delete_object(table.ref, #(key, value))
}

/// Delete all objects in the table (keeps the table open).
pub fn delete_all(from table: DuplicateBag(k, v)) -> Result(Nil, DetsError) {
  ffi_delete_all(table.ref)
}

// ── Info ────────────────────────────────────────────────────────────────

/// Get information about an open table.
pub fn info(table: DuplicateBag(k, v)) -> Result(slate.TableInfo, DetsError) {
  case ffi_info_file_size(table.ref), ffi_info_size(table.ref) {
    Ok(file_size), Ok(object_count) ->
      Ok(slate.TableInfo(
        file_size: file_size,
        object_count: object_count,
        kind: slate.DuplicateBag,
      ))
    Error(err), _ -> Error(err)
    _, Error(err) -> Error(err)
  }
}

fn tuple_decoder(
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Decoder(#(k, v)) {
  use k <- decode.field(0, key_decoder)
  use v <- decode.field(1, value_decoder)
  decode.success(#(k, v))
}

fn decode_entries(
  entries: List(Dynamic),
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Result(List(#(k, v)), DetsError) {
  let decoder = tuple_decoder(key_decoder, value_decoder)
  list.try_map(entries, fn(entry) {
    decode.run(entry, decoder)
    |> result.map_error(slate.DecodeErrors)
  })
}

// ── FFI bindings ────────────────────────────────────────────────────────

@external(erlang, "dets_ffi", "open_duplicate_bag")
fn ffi_open_duplicate_bag(
  path: String,
  repair: RepairPolicy,
) -> Result(TableRef, DetsError)

@external(erlang, "dets_ffi", "open_duplicate_bag_with_access")
fn ffi_open_duplicate_bag_with_access(
  path: String,
  repair: RepairPolicy,
  access: AccessMode,
) -> Result(TableRef, DetsError)

@external(erlang, "dets_ffi", "close")
fn ffi_close(ref: TableRef) -> Result(Nil, DetsError)

@external(erlang, "with_table_ffi", "with_close")
fn ffi_with_close(
  table: DuplicateBag(k, v),
  fun: fn(DuplicateBag(k, v)) -> Result(a, DetsError),
  close: fn(DuplicateBag(k, v)) -> Result(Nil, DetsError),
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
