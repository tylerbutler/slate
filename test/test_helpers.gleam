import gleam/list

/// Delete a test file, ignoring any deletion error.
pub fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
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
