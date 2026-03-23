import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/list

/// Delete a test file, ignoring any deletion error.
pub fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

/// Returns `True` when the provided function exits abnormally.
pub fn did_panic(fun: fn() -> a) -> Bool {
  ffi_did_panic(fun)
}

/// Returns `True` when the DETS table for `path` is currently open.
pub fn is_table_open(path: String) -> Bool {
  ffi_is_table_open(path)
}

/// Build an inclusive integer range from `from` to `to`.
///
/// Returns an empty list when `from > to`.
pub fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> range_loop(from, to, [])
  }
}

/// An unsafe decoder that accepts any value without type checking.
///
/// Only for use in tests where the types are known to be correct
/// within a single test (e.g., complex nested types like tuples of
/// tuples, Result values, etc.).
pub fn unsafe_decoder() -> Decoder(a) {
  decode.new_primitive_decoder("unsafe", fn(dyn) { Ok(unsafe_coerce(dyn)) })
}

fn range_loop(current: Int, to: Int, acc: List(Int)) -> List(Int) {
  case current > to {
    True -> list.reverse(acc)
    False -> range_loop(current + 1, to, [current, ..acc])
  }
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, DynError)

/// Dynamic Erlang error returned by `file:delete/1`.
type DynError

@external(erlang, "test_helpers_ffi", "did_panic")
fn ffi_did_panic(fun: fn() -> a) -> Bool

@external(erlang, "test_helpers_ffi", "is_table_open")
fn ffi_is_table_open(path: String) -> Bool

@external(erlang, "test_helpers_ffi", "identity")
fn unsafe_coerce(value: Dynamic) -> a
