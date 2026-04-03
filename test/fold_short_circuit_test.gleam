import gleam/dynamic/decode
import gleam/list
import startest/expect
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helpers.{cleanup, range}

@external(erlang, "fold_short_circuit_test_ffi", "count_ffi_fold_invocations")
fn count_ffi_fold_invocations(table: table_type) -> Int

const entry_count = 50

pub fn set_fold_short_circuits_on_decode_error_test() {
  let path = "test_set_fold_short_circuit.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(table, range(1, entry_count) |> list.map(fn(i) { #(i, i * 10) }))
  let assert Ok(Nil) = set.close(table)

  // 1. Verify the Gleam API correctly propagates the DecodeErrors
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Error(slate.DecodeErrors(_)) =
    set.fold(table2, "", fn(acc, _k, v) { acc <> v })

  // 2. Verify the underlying FFI fold actually aborts on the first error.
  //    (We test this by calling the FFI directly with a failing callback).
  let invocations = count_ffi_fold_invocations(table2)
  invocations |> expect.to_equal(1)

  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

pub fn bag_fold_short_circuits_on_decode_error_test() {
  let path = "test_bag_fold_short_circuit.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    bag.insert_list(table, range(1, entry_count) |> list.map(fn(i) { #(i, i * 10) }))
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Error(slate.DecodeErrors(_)) =
    bag.fold(table2, "", fn(acc, _k, v) { acc <> v })

  let invocations = count_ffi_fold_invocations(table2)
  invocations |> expect.to_equal(1)

  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

pub fn duplicate_bag_fold_short_circuits_on_decode_error_test() {
  let path = "test_dupbag_fold_short_circuit.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    duplicate_bag.insert_list(
      table,
      range(1, entry_count) |> list.map(fn(i) { #(i, i * 10) }),
    )
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )

  let assert Error(slate.DecodeErrors(_)) =
    duplicate_bag.fold(table2, "", fn(acc, _k, v) { acc <> v })

  let invocations = count_ffi_fold_invocations(table2)
  invocations |> expect.to_equal(1)

  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}
