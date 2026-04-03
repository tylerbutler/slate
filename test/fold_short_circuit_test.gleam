import gleam/dynamic/decode
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helpers.{cleanup}

@external(erlang, "fold_short_circuit_test_ffi", "reset_counter")
fn reset_counter() -> Nil

@external(erlang, "fold_short_circuit_test_ffi", "increment_counter")
fn increment_counter() -> Nil

@external(erlang, "fold_short_circuit_test_ffi", "get_counter")
fn get_counter() -> Int

const entry_count = 50

pub fn set_fold_short_circuits_on_decode_error_test() {
  let path = "test_set_fold_short_circuit.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  insert_set_entries(table, 1, entry_count)
  let assert Ok(Nil) = set.close(table)

  // Reopen with wrong value decoder to trigger decode errors
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  reset_counter()
  let result =
    set.fold(table2, "", fn(acc, _k, v) {
      increment_counter()
      acc <> v
    })
  let invocations = get_counter()

  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }

  // The callback should have been invoked far fewer times than entry_count,
  // because the fold short-circuits after the first decode error.
  { invocations < entry_count } |> expect.to_be_true()

  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

pub fn bag_fold_short_circuits_on_decode_error_test() {
  let path = "test_bag_fold_short_circuit.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  insert_bag_entries(table, 1, entry_count)
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)

  reset_counter()
  let result =
    bag.fold(table2, "", fn(acc, _k, v) {
      increment_counter()
      acc <> v
    })
  let invocations = get_counter()

  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }

  { invocations < entry_count } |> expect.to_be_true()

  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

pub fn duplicate_bag_fold_short_circuits_on_decode_error_test() {
  let path = "test_dupbag_fold_short_circuit.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  insert_duplicate_bag_entries(table, 1, entry_count)
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )

  reset_counter()
  let result =
    duplicate_bag.fold(table2, "", fn(acc, _k, v) {
      increment_counter()
      acc <> v
    })
  let invocations = get_counter()

  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }

  { invocations < entry_count } |> expect.to_be_true()

  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

fn insert_set_entries(table: set.Set(Int, Int), current: Int, max: Int) -> Nil {
  case current > max {
    True -> Nil
    False -> {
      let assert Ok(Nil) = set.insert(table, current, current * 10)
      insert_set_entries(table, current + 1, max)
    }
  }
}

fn insert_bag_entries(table: bag.Bag(Int, Int), current: Int, max: Int) -> Nil {
  case current > max {
    True -> Nil
    False -> {
      let assert Ok(Nil) = bag.insert(table, current, current * 10)
      insert_bag_entries(table, current + 1, max)
    }
  }
}

fn insert_duplicate_bag_entries(
  table: duplicate_bag.DuplicateBag(Int, Int),
  current: Int,
  max: Int,
) -> Nil {
  case current > max {
    True -> Nil
    False -> {
      let assert Ok(Nil) = duplicate_bag.insert(table, current, current * 10)
      insert_duplicate_bag_entries(table, current + 1, max)
    }
  }
}
