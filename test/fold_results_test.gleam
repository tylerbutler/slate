import gleam/dynamic/decode
import gleam/list
import gleam/string
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helpers.{cleanup, range}

// ── Success path ────────────────────────────────────────────────────────

pub fn set_fold_results_success_test() {
  let path = "test_set_fold_results_ok.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 10)
  let assert Ok(Nil) = set.insert(table, "b", 20)
  let assert Ok(Nil) = set.insert(table, "c", 30)

  let assert Ok(sum) =
    set.fold_results(table, 0, fn(acc, entry) {
      case entry {
        Ok(#(_k, v)) -> acc + v
        Error(_) -> acc
      }
    })
  sum |> expect.to_equal(60)

  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

pub fn bag_fold_results_success_test() {
  let path = "test_bag_fold_results_ok.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 1)
  let assert Ok(Nil) = bag.insert(table, "a", 2)
  let assert Ok(Nil) = bag.insert(table, "b", 3)

  let assert Ok(sum) =
    bag.fold_results(table, 0, fn(acc, entry) {
      case entry {
        Ok(#(_k, v)) -> acc + v
        Error(_) -> acc
      }
    })
  sum |> expect.to_equal(6)

  let assert Ok(Nil) = bag.close(table)
  cleanup(path)
}

pub fn duplicate_bag_fold_results_success_test() {
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
        Ok(#(_k, v)) -> acc + v
        Error(_) -> acc
      }
    })
  sum |> expect.to_equal(5)

  let assert Ok(Nil) = duplicate_bag.close(table)
  cleanup(path)
}

pub fn set_fold_results_empty_table_test() {
  let path = "test_set_fold_results_empty.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)

  let assert Ok(count) = set.fold_results(table, 0, fn(acc, _entry) { acc + 1 })
  count |> expect.to_equal(0)

  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}

// ── Partial failure — skip errors ───────────────────────────────────────

pub fn set_fold_results_skips_decode_errors_test() {
  let path = "test_set_fold_results_skip.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(table, range(1, 50) |> list.map(fn(i) { #(i, i * 10) }))
  let assert Ok(Nil) = set.close(table)

  // Reopen with wrong value decoder
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  // All entries fail to decode — skip pattern should yield empty list
  let assert Ok(items) =
    set.fold_results(table2, [], fn(acc, entry) {
      case entry {
        Ok(#(k, v)) -> [#(k, v), ..acc]
        Error(_) -> acc
      }
    })
  items |> expect.to_equal([])

  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

pub fn bag_fold_results_skips_decode_errors_test() {
  let path = "test_bag_fold_results_skip.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    bag.insert_list(table, range(1, 10) |> list.map(fn(i) { #(i, i * 10) }))
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Ok(items) =
    bag.fold_results(table2, [], fn(acc, entry) {
      case entry {
        Ok(#(k, v)) -> [#(k, v), ..acc]
        Error(_) -> acc
      }
    })
  items |> expect.to_equal([])

  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

pub fn duplicate_bag_fold_results_skips_decode_errors_test() {
  let path = "test_dupbag_fold_results_skip.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    duplicate_bag.insert_list(
      table,
      range(1, 10) |> list.map(fn(i) { #(i, i * 10) }),
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
        Ok(#(k, v)) -> [#(k, v), ..acc]
        Error(_) -> acc
      }
    })
  items |> expect.to_equal([])

  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

// ── Partial failure — partition pattern ─────────────────────────────────

pub fn set_fold_results_partition_test() {
  let path = "test_set_fold_results_partition.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(table, range(1, 20) |> list.map(fn(i) { #(i, i * 10) }))
  let assert Ok(Nil) = set.close(table)

  // Reopen with wrong decoder — all entries will fail
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Ok(#(good, bad)) =
    set.fold_results(table2, #([], []), fn(acc, entry) {
      case entry {
        Ok(#(k, v)) -> #([#(k, v), ..acc.0], acc.1)
        Error(errs) -> #(acc.0, [errs, ..acc.1])
      }
    })
  good |> expect.to_equal([])
  list.length(bad) |> expect.to_equal(20)

  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Visits all entries (no short-circuit) ───────────────────────────────

pub fn set_fold_results_visits_all_entries_test() {
  let path = "test_set_fold_results_all.dets"
  let count = 50
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(table, range(1, count) |> list.map(fn(i) { #(i, i * 10) }))
  let assert Ok(Nil) = set.close(table)

  // Wrong decoder — every entry fails, but we count them all
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Ok(visited) =
    set.fold_results(table2, 0, fn(acc, _entry) { acc + 1 })
  visited |> expect.to_equal(count)

  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Collect keys with correct key decoder ───────────────────────────────

pub fn set_fold_results_collects_keys_test() {
  let path = "test_set_fold_results_keys.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert_list(table, [#("a", 1), #("b", 2), #("c", 3)])

  let assert Ok(keys) =
    set.fold_results(table, [], fn(acc, entry) {
      case entry {
        Ok(#(k, _v)) -> [k, ..acc]
        Error(_) -> acc
      }
    })
  keys |> list.sort(string.compare) |> expect.to_equal(["a", "b", "c"])

  let assert Ok(Nil) = set.close(table)
  cleanup(path)
}
