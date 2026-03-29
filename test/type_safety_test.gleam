/// Tests verifying runtime type safety via decoders.
///
/// These tests confirm that opening a DETS file with the wrong type
/// decoders produces DecodeErrors instead of silently returning
/// incorrectly-typed data.
import gleam/dynamic/decode
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import startest/expect
import test_helpers.{cleanup}

// ── Set: wrong value decoder ────────────────────────────────────────────

pub fn set_wrong_value_decoder_lookup_test() {
  let path = "test_ts_set_wrong_val.dets"
  // Write as String/Int
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 42)
  let assert Ok(Nil) = set.close(table)
  // Reopen with wrong value decoder (String instead of Int)
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let result = set.lookup(table2, key: "key")
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

pub fn set_wrong_value_decoder_to_list_test() {
  let path = "test_ts_set_wrong_to_list.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 1)
  let assert Ok(Nil) = set.insert(table, "b", 2)
  let assert Ok(Nil) = set.close(table)
  // Reopen with wrong value decoder
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let result = set.to_list(table2)
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

pub fn set_wrong_value_decoder_fold_test() {
  let path = "test_ts_set_wrong_fold.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "a", 100)
  let assert Ok(Nil) = set.close(table)
  // Reopen with wrong value decoder
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let result = set.fold(table2, "", fn(acc, _k, v) { acc <> v })
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Set: correct decoders still work ────────────────────────────────────

pub fn set_correct_decoders_work_test() {
  let path = "test_ts_set_correct.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "x", 99)
  let assert Ok(Nil) = set.close(table)
  // Reopen with correct decoders
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(99) = set.lookup(table2, key: "x")
  let assert Ok(entries) = set.to_list(table2)
  entries |> expect.to_equal([#("x", 99)])
  let assert Ok(sum) = set.fold(table2, 0, fn(acc, _k, v) { acc + v })
  sum |> expect.to_equal(99)
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}

// ── Bag: wrong value decoder ────────────────────────────────────────────

pub fn bag_wrong_value_decoder_lookup_test() {
  let path = "test_ts_bag_wrong_val.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "key", 42)
  let assert Ok(Nil) = bag.insert(table, "key", 99)
  let assert Ok(Nil) = bag.close(table)
  // Reopen with wrong value decoder
  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let result = bag.lookup(table2, key: "key")
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

pub fn bag_wrong_value_decoder_fold_test() {
  let path = "test_ts_bag_wrong_fold.dets"
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = bag.insert(table, "a", 10)
  let assert Ok(Nil) = bag.close(table)
  let assert Ok(table2) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let result = bag.fold(table2, "", fn(acc, _k, v) { acc <> v })
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = bag.close(table2)
  cleanup(path)
}

// ── DuplicateBag: wrong value decoder ───────────────────────────────────

pub fn dupbag_wrong_value_decoder_lookup_test() {
  let path = "test_ts_dupbag_wrong_val.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", 42)
  let assert Ok(Nil) = duplicate_bag.insert(table, "key", 42)
  let assert Ok(Nil) = duplicate_bag.close(table)
  // Reopen with wrong value decoder
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = duplicate_bag.lookup(table2, key: "key")
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

pub fn dupbag_wrong_value_decoder_to_list_test() {
  let path = "test_ts_dupbag_wrong_to_list.dets"
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = duplicate_bag.insert(table, "a", 1)
  let assert Ok(Nil) = duplicate_bag.close(table)
  let assert Ok(table2) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.string,
    )
  let result = duplicate_bag.to_list(table2)
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = duplicate_bag.close(table2)
  cleanup(path)
}

// ── Wrong key decoder ───────────────────────────────────────────────────

pub fn set_wrong_key_decoder_to_list_test() {
  let path = "test_ts_set_wrong_key.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "key", 42)
  let assert Ok(Nil) = set.close(table)
  // Reopen with wrong KEY decoder (Int instead of String)
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.int, value_decoder: decode.int)
  let result = set.to_list(table2)
  case result {
    Error(slate.DecodeErrors(_)) -> Nil
    other -> other |> expect.to_equal(Error(slate.NotFound))
  }
  let assert Ok(Nil) = set.close(table2)
  cleanup(path)
}
