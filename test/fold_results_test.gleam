import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/string
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

pub fn set_result_shaped_accumulators_test() -> Nil {
  let path = "test_set_result_accumulators.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  check_accumulator(
    fn(initial, callback) { set.fold_results(table, initial, callback) },
    Error(0),
    0,
  )
  let assert Ok(Nil) = set.insert_list(table, [#(1, 1), #(2, 2), #(3, 3)])
  check_accumulator(
    fn(initial, callback) { set.fold_results(table, initial, callback) },
    Error(0),
    3,
  )
  check_accumulator(
    fn(initial, callback) { set.fold_results(table, initial, callback) },
    Error(slate.DecodeErrors([])),
    3,
  )
  check_accumulator(
    fn(initial, callback) { set.fold_results(table, initial, callback) },
    Ok(Error(Ok(7))),
    3,
  )
  assert set.fold(table, Error(0), fn(_, _, _) { Error(1) }) == Ok(Error(1))
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn bag_result_shaped_accumulators_test() -> Nil {
  let path = "test_bag_result_accumulators.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  check_accumulator(
    fn(initial, callback) { bag.fold_results(table, initial, callback) },
    Error(0),
    0,
  )
  let assert Ok(Nil) = bag.insert_list(table, [#(1, 1), #(2, 2), #(3, 3)])
  check_accumulator(
    fn(initial, callback) { bag.fold_results(table, initial, callback) },
    Error(0),
    3,
  )
  check_accumulator(
    fn(initial, callback) { bag.fold_results(table, initial, callback) },
    Error(slate.DecodeErrors([])),
    3,
  )
  check_accumulator(
    fn(initial, callback) { bag.fold_results(table, initial, callback) },
    Ok(Error(Ok(7))),
    3,
  )
  assert bag.fold(table, Error(0), fn(_, _, _) { Error(1) }) == Ok(Error(1))
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_result_shaped_accumulators_test() -> Nil {
  let path = "test_duplicate_bag_result_accumulators.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  check_accumulator(
    fn(initial, callback) {
      duplicate_bag.fold_results(table, initial, callback)
    },
    Error(0),
    0,
  )
  let assert Ok(Nil) =
    duplicate_bag.insert_list(table, [#(1, 1), #(2, 2), #(3, 3)])
  check_accumulator(
    fn(initial, callback) {
      duplicate_bag.fold_results(table, initial, callback)
    },
    Error(0),
    3,
  )
  check_accumulator(
    fn(initial, callback) {
      duplicate_bag.fold_results(table, initial, callback)
    },
    Error(slate.DecodeErrors([])),
    3,
  )
  check_accumulator(
    fn(initial, callback) {
      duplicate_bag.fold_results(table, initial, callback)
    },
    Ok(Error(Ok(7))),
    3,
  )
  assert duplicate_bag.fold(table, Error(0), fn(_, _, _) { Error(1) })
    == Ok(Error(1))
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

fn check_accumulator(
  fold: fn(acc, fn(acc, Result(#(Int, Int), List(decode.DecodeError))) -> acc) ->
    Result(acc, slate.DetsError),
  initial: acc,
  count: Int,
) -> Nil {
  let visits = process.new_subject()
  assert fold(initial, fn(accumulator, entry) {
      let assert Ok(_) = entry
      process.send(visits, Nil)
      accumulator
    })
    == Ok(initial)
  list.each(test_helper.range(1, count), fn(_) {
    assert process.receive(visits, 0) == Ok(Nil)
  })
  assert process.receive(visits, 0) == Error(Nil)
}

// ── Success path ────────────────────────────────────────────────────────

pub fn set_fold_results_success_test() -> Nil {
  let path = "test_set_fold_results_ok.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 10)
  let assert Ok(Nil) = set.insert(table, "b", 20)
  let assert Ok(Nil) = set.insert(table, "c", 30)

  let assert Ok(sum) =
    set.fold_results(table, 0, fn(acc, entry) {
      case entry {
        Ok(#(_key, value)) -> acc + value
        Error(_) -> acc
      }
    })
  assert sum == 60

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn bag_fold_results_success_test() -> Nil {
  let path = "test_bag_fold_results_ok.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "a", 2)
  let assert Ok(Nil) = bag.insert(table, "b", 3)

  let assert Ok(sum) =
    bag.fold_results(table, 0, fn(acc, entry) {
      case entry {
        Ok(#(_key, value)) -> acc + value
        Error(_) -> acc
      }
    })
  assert sum == 6

  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_fold_results_success_test() -> Nil {
  let path = "test_dupbag_fold_results_ok.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.insert(table, "b", 3)

  let assert Ok(sum) =
    duplicate_bag.fold_results(table, 0, fn(acc, entry) {
      case entry {
        Ok(#(_key, value)) -> acc + value
        Error(_) -> acc
      }
    })
  assert sum == 5

  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn set_fold_results_empty_table_test() -> Nil {
  let path = "test_set_fold_results_empty.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)

  let assert Ok(count) = set.fold_results(table, 0, fn(acc, _entry) { acc + 1 })
  assert count == 0

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Partial failure — skip errors ───────────────────────────────────────

pub fn set_fold_results_skips_decode_errors_test() -> Nil {
  let path = "test_set_fold_results_skip.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(
      table,
      test_helper.range(1, 50) |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = set.close(table)

  // Reopen with wrong value decoder
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  // All entries fail to decode — skip pattern should yield empty list
  let assert Ok(items) =
    set.fold_results(table2, [], fn(acc, entry) {
      case entry {
        Ok(#(key, value)) -> [#(key, value), ..acc]
        Error(_) -> acc
      }
    })
  assert items == []

  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

pub fn bag_fold_results_skips_decode_errors_test() -> Nil {
  let path = "test_bag_fold_results_skip.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    bag.insert_list(
      table,
      test_helper.range(1, 10) |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Ok(items) =
    bag.fold_results(table2, [], fn(acc, entry) {
      case entry {
        Ok(#(key, value)) -> [#(key, value), ..acc]
        Error(_) -> acc
      }
    })
  assert items == []

  let assert Ok(Nil) = bag.close(table2)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_fold_results_skips_decode_errors_test() -> Nil {
  let path = "test_dupbag_fold_results_skip.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    duplicate_bag.insert_list(
      table,
      test_helper.range(1, 10) |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )

  let assert Ok(items) =
    duplicate_bag.fold_results(table2, [], fn(acc, entry) {
      case entry {
        Ok(#(key, value)) -> [#(key, value), ..acc]
        Error(_) -> acc
      }
    })
  assert items == []

  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}

// ── Partial failure — partition pattern ─────────────────────────────────

pub fn set_fold_results_partition_test() -> Nil {
  let path = "test_set_fold_results_partition.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(
      table,
      test_helper.range(1, 20) |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = set.close(table)

  // Reopen with wrong decoder — all entries will fail
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Ok(#(good, bad)) =
    set.fold_results(table2, #([], []), fn(accumulator, entry) {
      let #(entries, decode_errors) = accumulator
      case entry {
        Ok(#(key, value)) -> #([#(key, value), ..entries], decode_errors)
        Error(errors) -> #(entries, [errors, ..decode_errors])
      }
    })
  assert good == []
  assert list.length(bad) == 20

  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

// ── Visits all entries (no short-circuit) ───────────────────────────────

pub fn set_fold_results_visits_all_entries_test() -> Nil {
  let path = "test_set_fold_results_all.dets"
  let count = 50
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(
      table,
      test_helper.range(1, count) |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = set.close(table)

  // Wrong decoder — every entry fails, but we count them all
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Ok(visited) =
    set.fold_results(table2, 0, fn(acc, _entry) { acc + 1 })
  assert visited == count

  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

// ── Collect keys with correct key decoder ───────────────────────────────

pub fn set_fold_results_collects_keys_test() -> Nil {
  let path = "test_set_fold_results_keys.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])

  let assert Ok(keys) =
    set.fold_results(table, [], fn(acc, entry) {
      case entry {
        Ok(#(key, _value)) -> [key, ..acc]
        Error(_) -> acc
      }
    })
  assert { keys |> list.sort(string.compare) } == ["a", "b", "c"]

  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}
