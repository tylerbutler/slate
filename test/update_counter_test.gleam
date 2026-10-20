//// Tests for update_counter API on set tables.
//// Adapted from OTP dets_SUITE update_counter test.

import gleam/dynamic/decode
import slate
import slate/set
import test_helper

pub fn update_counter_float_is_unchanged_test() -> Nil {
  let path = "test_counter_float.dets"
  let assert Ok(writer) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.float)
  let assert Ok(Nil) = set.insert(writer, "hits", 1.5)
  let assert Ok(Nil) = set.close(writer)
  let assert Ok(counter) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  assert set.update_counter(counter, "hits", 1)
    == Error(set.CounterValueNotInteger)
  let assert Ok(Nil) = set.close(counter)
  let assert Ok(reader) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.float)
  assert set.lookup(reader, "hits") == Ok(1.5)
  let assert Ok(Nil) = set.close(reader)

  let assert Ok(read_only) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Error(set.TableError(slate.AccessDenied(_))) =
    set.update_counter(read_only, "hits", 1)
  let assert Error(set.TableError(slate.AccessDenied(_))) =
    set.update_counter(read_only, "missing", 1)
  let assert Ok(Nil) = set.close(read_only)
  test_helper.cleanup(path)
}

// ── Basic increment ─────────────────────────────────────────────────────

pub fn update_counter_basic_test() -> Nil {
  let path = "test_counter_basic.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "hits", 0)
  let assert Ok(1) = set.update_counter(table, "hits", 1)
  let assert Ok(2) = set.update_counter(table, "hits", 1)
  let assert Ok(3) = set.update_counter(table, "hits", 1)
  // Verify via lookup
  let assert Ok(3) = set.lookup(table, key: "hits")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Increment by various amounts ────────────────────────────────────────

pub fn update_counter_by_amount_test() -> Nil {
  let path = "test_counter_amount.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "score", 0)
  let assert Ok(10) = set.update_counter(table, "score", 10)
  let assert Ok(110) = set.update_counter(table, "score", 100)
  let assert Ok(110) = set.lookup(table, key: "score")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Negative increment (decrement) ──────────────────────────────────────

pub fn update_counter_decrement_test() -> Nil {
  let path = "test_counter_dec.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "balance", 100)
  let assert Ok(75) = set.update_counter(table, "balance", -25)
  let assert Ok(50) = set.update_counter(table, "balance", -25)
  let assert Ok(50) = set.lookup(table, key: "balance")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Counter goes negative ───────────────────────────────────────────────

pub fn update_counter_goes_negative_test() -> Nil {
  let path = "test_counter_neg.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "temp", 0)
  let assert Ok(-10) = set.update_counter(table, "temp", -10)
  let assert Ok(-10) = set.lookup(table, key: "temp")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Counter persists across close/reopen ────────────────────────────────

pub fn update_counter_persistence_test() -> Nil {
  let path = "test_counter_persist.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "counter", 0)
  let assert Ok(5) = set.update_counter(table, "counter", 5)
  let assert Ok(Nil) = set.close(table)
  // Reopen and continue counting
  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(5) = set.lookup(table2, key: "counter")
  let assert Ok(8) = set.update_counter(table2, "counter", 3)
  let assert Ok(8) = set.lookup(table2, key: "counter")
  let assert Ok(Nil) = set.close(table2)
  test_helper.cleanup(path)
}

// ── Counter with non-existent key fails ─────────────────────────────────

pub fn update_counter_missing_key_test() -> Nil {
  let path = "test_counter_missing.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let result = set.update_counter(table, "missing", 1)
  assert result == Error(set.TableError(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn update_counter_closed_table_test() -> Nil {
  let path = "test_counter_closed.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "hits", 0)
  let assert Ok(Nil) = set.close(table)

  assert set.update_counter(table, "hits", 1)
    == Error(set.TableError(slate.TableDoesNotExist))

  test_helper.cleanup(path)
}

// ── Increment by zero ───────────────────────────────────────────────────

pub fn update_counter_by_zero_test() -> Nil {
  let path = "test_counter_zero.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "stable", 42)
  let assert Ok(42) = set.update_counter(table, "stable", 0)
  let assert Ok(42) = set.lookup(table, key: "stable")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Multiple counters in same table ─────────────────────────────────────

pub fn update_counter_multiple_keys_test() -> Nil {
  let path = "test_counter_multi.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "page_views", 0)
  let assert Ok(Nil) = set.insert(table, "api_calls", 0)
  let assert Ok(Nil) = set.insert(table, "errors", 0)
  let assert Ok(1) = set.update_counter(table, "page_views", 1)
  let assert Ok(2) = set.update_counter(table, "page_views", 1)
  let assert Ok(1) = set.update_counter(table, "api_calls", 1)
  let assert Ok(1) = set.update_counter(table, "errors", 1)
  let assert Ok(2) = set.update_counter(table, "errors", 1)
  let assert Ok(3) = set.update_counter(table, "errors", 1)
  let assert Ok(2) = set.lookup(table, key: "page_views")
  let assert Ok(1) = set.lookup(table, key: "api_calls")
  let assert Ok(3) = set.lookup(table, key: "errors")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Large increment ─────────────────────────────────────────────────────

pub fn update_counter_large_increment_test() -> Nil {
  let path = "test_counter_large.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "big", 0)
  let assert Ok(1_000_000) = set.update_counter(table, "big", 1_000_000)
  let assert Ok(2_000_000) = set.update_counter(table, "big", 1_000_000)
  let assert Ok(2_000_000) = set.lookup(table, key: "big")
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

// ── Counter with non-integer value fails ─────────────────────────────────

pub fn update_counter_non_integer_value_test() -> Nil {
  let path = "test_counter_nonint.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  let assert Ok(Nil) = set.insert(table, "hits", "not_an_int")
  let assert Ok(Nil) = set.close(table)

  let assert Ok(table2) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let result = set.update_counter(table2, "hits", 1)
  assert result == Error(set.CounterValueNotInteger)
  let assert Ok(Nil) = set.close(table2)
  let assert Ok(reader) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.string)
  assert set.lookup(reader, "hits") == Ok("not_an_int")
  let assert Ok(Nil) = set.close(reader)
  test_helper.cleanup(path)
}
