/// DETS bag tables — multiple distinct values per key.
///
/// Bag tables allow storing multiple values for the same key, but
/// duplicate key-value pairs are silently ignored.
///
/// ## Example
///
/// ```gleam
/// import dets/bag
///
/// let assert Ok(table) = bag.open("tags.dets")
/// let assert Ok(Nil) = bag.insert(table, "color", "red")
/// let assert Ok(Nil) = bag.insert(table, "color", "blue")
/// let assert Ok(["red", "blue"]) = bag.lookup(table, "color")
/// let assert Ok(Nil) = bag.close(table)
/// ```
///
import slate.{type DetsError, type RepairPolicy, AutoRepair}

/// An open DETS bag table with typed keys and values.
pub opaque type Bag(k, v) {
  Bag(ref: TableRef)
}

/// Internal reference to the DETS table (Erlang atom).
type TableRef

// ── Lifecycle ───────────────────────────────────────────────────────────

/// Open or create a DETS bag table at the given file path.
pub fn open(path: String) -> Result(Bag(k, v), DetsError) {
  open_with(path, AutoRepair)
}

/// Open or create a DETS bag table with repair options.
pub fn open_with(
  path: String,
  repair: RepairPolicy,
) -> Result(Bag(k, v), DetsError) {
  case ffi_open_bag(path, repair) {
    Ok(ref) -> Ok(Bag(ref:))
    Error(err) -> Error(err)
  }
}

/// Close the table, flushing all pending writes to disk.
pub fn close(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_close(table.ref)
}

/// Flush pending writes to disk without closing the table.
pub fn sync(table: Bag(k, v)) -> Result(Nil, DetsError) {
  ffi_sync(table.ref)
}

/// Use a table within a callback, ensuring it is closed afterward.
pub fn with_table(
  path: String,
  fun: fn(Bag(k, v)) -> Result(a, DetsError),
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

/// Look up all values for a key. Returns an empty list if key not found.
pub fn lookup(from table: Bag(k, v), key key: k) -> Result(List(v), DetsError) {
  ffi_lookup_all(table.ref, key)
}

/// Check if a key exists without returning the values.
pub fn member(of table: Bag(k, v), key key: k) -> Result(Bool, DetsError) {
  ffi_member(table.ref, key)
}

/// Return all key-value pairs as a list.
///
/// **Warning**: loads entire table into memory.
pub fn to_list(from table: Bag(k, v)) -> Result(List(#(k, v)), DetsError) {
  ffi_to_list(table.ref)
}

/// Fold over all entries. Order is unspecified.
pub fn fold(
  over table: Bag(k, v),
  from initial: acc,
  with fun: fn(acc, k, v) -> acc,
) -> Result(acc, DetsError) {
  let wrapper = fn(entry: #(k, v), acc: acc) -> acc {
    fun(acc, entry.0, entry.1)
  }
  ffi_fold(table.ref, wrapper, initial)
}

/// Return the number of objects stored.
pub fn size(of table: Bag(k, v)) -> Result(Int, DetsError) {
  ffi_info_size(table.ref)
}

// ── Write ───────────────────────────────────────────────────────────────

/// Insert a key-value pair. Duplicate key-value pairs are ignored.
pub fn insert(
  into table: Bag(k, v),
  key key: k,
  value value: v,
) -> Result(Nil, DetsError) {
  ffi_insert(table.ref, #(key, value))
}

/// Insert multiple key-value pairs.
pub fn insert_list(
  into table: Bag(k, v),
  entries entries: List(#(k, v)),
) -> Result(Nil, DetsError) {
  ffi_insert_list(table.ref, entries)
}

// ── Delete ──────────────────────────────────────────────────────────────

/// Delete all values for the given key.
pub fn delete_key(from table: Bag(k, v), key key: k) -> Result(Nil, DetsError) {
  ffi_delete_key(table.ref, key)
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
      Ok(slate.TableInfo(
        file_size: file_size,
        object_count: object_count,
        kind: slate.Bag,
      ))
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

@external(erlang, "dets_ffi", "lookup_all")
fn ffi_lookup_all(ref: TableRef, key: k) -> Result(List(v), DetsError)

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

@external(erlang, "dets_ffi", "delete_key")
fn ffi_delete_key(ref: TableRef, key: k) -> Result(Nil, DetsError)

@external(erlang, "dets_ffi", "delete_all")
fn ffi_delete_all(ref: TableRef) -> Result(Nil, DetsError)
