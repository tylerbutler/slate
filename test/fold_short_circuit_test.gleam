import gleam/dynamic/decode
import gleam/list
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

@external(erlang, "fold_short_circuit_test_ffi", "count_ffi_fold_invocations")
fn count_ffi_fold_invocations(table: table_type) -> Int

const entry_count = 50

pub fn set_callback_exception_details_test() -> Nil {
  let path = "test_set_exception_details.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, 1, 1)
  check_exception_preservation(fn(raise) {
    set.fold(table, 0, fn(_, _, _) { raise() })
  })
  check_exception_preservation(fn(raise) {
    set.fold_results(table, 0, fn(_, _) { raise() })
  })
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn bag_callback_exception_details_test() -> Nil {
  let path = "test_bag_exception_details.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, 1, 1)
  check_exception_preservation(fn(raise) {
    bag.fold(table, 0, fn(_, _, _) { raise() })
  })
  check_exception_preservation(fn(raise) {
    bag.fold_results(table, 0, fn(_, _) { raise() })
  })
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_callback_exception_details_test() -> Nil {
  let path = "test_duplicate_bag_exception_details.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) = duplicate_bag.insert(table, 1, 1)
  check_exception_preservation(fn(raise) {
    duplicate_bag.fold(table, 0, fn(_, _, _) { raise() })
  })
  check_exception_preservation(fn(raise) {
    duplicate_bag.fold_results(table, 0, fn(_, _) { raise() })
  })
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

@external(erlang, "fold_short_circuit_test_ffi", "check_exception_preservation")
fn check_exception_preservation(
  run: fn(fn() -> Int) -> Result(Int, slate.DetsError),
) -> Nil

pub fn set_fold_short_circuits_on_decode_error_test() -> Nil {
  let path = "test_set_fold_short_circuit.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    set.insert_list(
      table,
      test_helper.range(1, entry_count)
        |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = set.close(table)

  // 1. Verify the Gleam API correctly propagates the DecodeErrors
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Error(slate.DecodeErrors(_)) =
    set.fold(table2, "", fn(acc, _key, value) { acc <> value })

  // 2. Verify the underlying FFI fold actually aborts on the first error.
  //    (We test this by calling the FFI directly with a failing callback).
  let invocations = count_ffi_fold_invocations(table2)
  assert invocations == 1

  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

pub fn bag_fold_short_circuits_on_decode_error_test() -> Nil {
  let path = "test_bag_fold_short_circuit.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    bag.insert_list(
      table,
      test_helper.range(1, entry_count)
        |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = bag.close(table)

  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.int, value_decoder: decode.string)

  let assert Error(slate.DecodeErrors(_)) =
    bag.fold(table2, "", fn(acc, _key, value) { acc <> value })

  let invocations = count_ffi_fold_invocations(table2)
  assert invocations == 1

  let assert Ok(Nil) = bag.close(table2)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_fold_short_circuits_on_decode_error_test() -> Nil {
  let path = "test_dupbag_fold_short_circuit.dets"
  let assert Ok(table) =
    duplicate_bag.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let assert Ok(Nil) =
    duplicate_bag.insert_list(
      table,
      test_helper.range(1, entry_count)
        |> list.map(fn(key) { #(key, key * 10) }),
    )
  let assert Ok(Nil) = duplicate_bag.close(table)

  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.int,
      value_decoder: decode.string,
    )

  let assert Error(slate.DecodeErrors(_)) =
    duplicate_bag.fold(table2, "", fn(acc, _key, value) { acc <> value })

  let invocations = count_ffi_fold_invocations(table2)
  assert invocations == 1

  let assert Ok(Nil) = duplicate_bag.close(table2)
  test_helper.cleanup(path)
}

pub fn set_fold_callback_panic_propagates_test() -> Nil {
  let path = "test_set_fold_panic.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, 1, "one")

  assert test_helper.did_panic(fn() {
    let _ =
      set.fold(table, "", fn(acc, _key, value) {
        let _ = acc <> value
        panic as "boom"
      })
    Nil
  })

  let assert Ok("one") = set.lookup(table, key: 1)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn set_fold_results_callback_panic_propagates_test() -> Nil {
  let path = "test_set_fold_results_panic.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, 1, "one")

  assert test_helper.did_panic(fn() {
    let _ =
      set.fold_results(table, 0, fn(acc, _entry) {
        let _ = acc
        panic as "boom"
      })
    Nil
  })

  let assert Ok("one") = set.lookup(table, key: 1)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}
