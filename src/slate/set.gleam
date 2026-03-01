/// DETS set tables — one value per key.
///
/// Set tables store key-value pairs where each key maps to exactly one value.
/// Inserting with an existing key overwrites the previous value.
///
/// ## Example
///
/// ```gleam
/// import dets/set
///
/// let assert Ok(table) = set.open("users.dets")
/// let assert Ok(Nil) = set.insert(table, "alice", 42)
/// let assert Ok(42) = set.lookup(table, "alice")
/// let assert Ok(Nil) = set.close(table)
/// ```
///
import slate.{type DetsError, type RepairPolicy, AutoRepair}

/// An open DETS set table with typed keys and values.
pub opaque type Set(k, v) {
  Set(ref: TableRef)
}

/// Internal reference to the DETS table (Erlang atom).
type TableRef

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open or create a DETS set table at the given file path.
///
/// If the file exists, it is opened. If it does not exist, a new table
/// is created. The table must be closed with `close` when no longer needed.
///
/// ```gleam
/// let assert Ok(table) = set.open("data/cache.dets")
/// ```
///
pub fn open(path: String) -> Result(Set(k, v), DetsError) {
  open_with(path, AutoRepair)
}

/// Open or create a DETS set table with repair options.
pub fn open_with(
  path: String,
  repair: RepairPolicy,
) -> Result(Set(k, v), DetsError) {
  case ffi_open_set(path, repair) {
    Ok(ref) -> Ok(Set(ref:))
    Error(err) -> Error(err)
  }
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
/// use table <- set.with_table("data/cache.dets")
/// set.insert(table, "key", "value")
/// ```
///
pub fn with_table(
  path: String,
  fun: fn(Set(k, v)) -> Result(a, DetsError),
) -> Result(a, DetsError) {
  case open(path) {
    Ok(table) -> {
      let result = fun(table)
      let _ = close(table)
      result
    }
    Error(err) -> Error(err)
  }
}

// ── Read ────────────────────────────────────────────────────────────────

/// Look up the value for a key.
///
/// Returns `Error(NotFound)` if the key does not exist.
pub fn lookup(from table: Set(k, v), key key: k) -> Result(v, DetsError) {
  ffi_lookup(table.ref, key)
}

/// Check if a key exists without returning the value.
pub fn member(of table: Set(k, v), key key: k) -> Result(Bool, DetsError) {
  ffi_member(table.ref, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
pub fn to_list(from table: Set(k, v)) -> Result(List(#(k, v)), DetsError) {
  ffi_to_list(table.ref)
}

/// Fold over all entries. Order is unspecified.
pub fn fold(
  over table: Set(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, DetsError) {
  let wrapper = fn(entry: #(k, v), acc: acc) -> acc {
    fun(acc, entry.0, entry.1)
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
/// For set tables this is equivalent to `delete_key` since each key
/// has at most one value. Provided for API consistency with bag tables.
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
/// Returns an error if the key doesn't exist or the value is not an integer.
///
/// ```gleam
/// let assert Ok(table) = set.open("counters.dets")
/// let assert Ok(Nil) = set.insert(table, "hits", 0)
/// let assert Ok(1) = set.update_counter(table, "hits", 1)
/// let assert Ok(3) = set.update_counter(table, "hits", 2)
/// ```
///
pub fn update_counter(
  in table: Set(k, Int),
  key key: k,
  increment amount: Int,
) -> Result(Int, DetsError) {
  ffi_update_counter(table.ref, key, amount)
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

@external(erlang, "dets_ffi", "close")
fn ffi_close(ref: TableRef) -> Result(Nil, DetsError)

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
fn ffi_lookup(ref: TableRef, key: k) -> Result(v, DetsError)

@external(erlang, "dets_ffi", "member")
fn ffi_member(ref: TableRef, key: k) -> Result(Bool, DetsError)

@external(erlang, "dets_ffi", "to_list")
fn ffi_to_list(ref: TableRef) -> Result(List(#(k, v)), DetsError)

@external(erlang, "dets_ffi", "fold")
fn ffi_fold(
  ref: TableRef,
  fun: fn(#(k, v), acc) -> acc,
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
) -> Result(Int, DetsError)

@external(erlang, "dets_ffi", "delete_key")
fn ffi_delete_key(ref: TableRef, key: k) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "delete_object")
fn ffi_delete_object(ref: TableRef, object: #(k, v)) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "delete_all")
fn ffi_delete_all(ref: TableRef) -> Result(Nil, DetsError)
