pub fn cleanup(path: String) {
  let _ = delete_file(path)
  Nil
}

pub fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}

@external(erlang, "file", "delete")
fn delete_file(path: String) -> Result(Nil, DynError)

type DynError
