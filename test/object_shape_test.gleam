import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import slate
import slate/bag
import slate/duplicate_bag
import slate/set
import test_helper

type TableType {
  Set
  Bag
  DuplicateBag
}

type FixtureError

@external(erlang, "test_helpers_ffi", "write_raw_objects")
fn write_raw_objects(
  path: String,
  table_type: TableType,
  objects: List(Dynamic),
) -> Result(Nil, FixtureError)

@external(erlang, "test_helpers_ffi", "read_raw_objects")
fn read_raw_objects(path: String) -> Result(List(Dynamic), FixtureError)

fn pair(key: String, value: Int) -> Dynamic {
  dynamic.array([dynamic.string(key), dynamic.int(value)])
}

fn malformed_objects() -> List(Dynamic) {
  [
    dynamic.array([dynamic.string("short")]),
    dynamic.array([dynamic.string("long"), dynamic.int(1), dynamic.int(2)]),
  ]
}

fn expect_decode_error(result: Result(a, slate.DetsError)) -> Nil {
  let assert Error(slate.DecodeErrors([_, ..])) = result
  Nil
}

pub fn set_lookup_exact_pair_test() -> Nil {
  let path = "test_set_object_shape.dets"
  test_helper.cleanup(path)
  let assert Ok(Nil) =
    write_raw_objects(path, Set, [pair("valid", 42), ..malformed_objects()])
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  expect_decode_error(set.lookup(table, "short"))
  expect_decode_error(set.lookup(table, "long"))
  assert set.lookup(table, "valid") == Ok(42)
  assert set.lookup(table, "missing") == Error(slate.NotFound)
  expect_decode_error(set.to_list(table))
  expect_decode_error(set.fold(table, 0, fn(count, _, _) { count + 1 }))
  assert set.fold_results(table, 0, fn(count, entry) {
      case entry {
        Ok(_) -> count
        Error(_) -> count + 1
      }
    })
    == Ok(2)
  let assert Ok(Nil) = set.close(table)
  assert set.lookup(table, "long") == Error(slate.TableDoesNotExist)
  let assert Ok(table) =
    set.open(
      path,
      key_decoder: decode.failure("", "accepted key"),
      value_decoder: decode.int,
    )
  expect_decode_error(set.lookup(table, "valid"))
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn bag_lookup_exact_pairs_test() -> Nil {
  let path = "test_bag_object_shape.dets"
  test_helper.cleanup(path)
  let assert Ok(Nil) =
    write_raw_objects(path, Bag, [
      pair("short", 7),
      pair("long", 8),
      pair("valid", 42),
      pair("valid", 43),
      ..malformed_objects()
    ])
  let assert Ok(table) =
    bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
  expect_decode_error(bag.lookup(table, "short"))
  expect_decode_error(bag.lookup(table, "long"))
  let assert Ok(values) = bag.lookup(table, "valid")
  assert list.sort(values, int.compare) == [42, 43]
  assert bag.lookup(table, "missing") == Ok([])
  expect_decode_error(bag.to_list(table))
  expect_decode_error(bag.fold(table, 0, fn(count, _, _) { count + 1 }))
  assert bag.fold_results(table, 0, fn(count, entry) {
      case entry {
        Ok(_) -> count
        Error(_) -> count + 1
      }
    })
    == Ok(2)
  let assert Ok(Nil) = bag.close(table)
  assert bag.lookup(table, "long") == Error(slate.TableDoesNotExist)
  let assert Ok(table) =
    bag.open(
      path,
      key_decoder: decode.failure("", "accepted key"),
      value_decoder: decode.int,
    )
  expect_decode_error(bag.lookup(table, "valid"))
  let assert Ok(Nil) = bag.close(table)
  test_helper.cleanup(path)
}

pub fn duplicate_bag_lookup_exact_pairs_test() -> Nil {
  let path = "test_duplicate_bag_object_shape.dets"
  test_helper.cleanup(path)
  let assert Ok(Nil) =
    write_raw_objects(path, DuplicateBag, [
      pair("short", 7),
      pair("long", 8),
      pair("valid", 42),
      pair("valid", 42),
      ..malformed_objects()
    ])
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  expect_decode_error(duplicate_bag.lookup(table, "short"))
  expect_decode_error(duplicate_bag.lookup(table, "long"))
  assert duplicate_bag.lookup(table, "valid") == Ok([42, 42])
  assert duplicate_bag.lookup(table, "missing") == Ok([])
  expect_decode_error(duplicate_bag.to_list(table))
  expect_decode_error(
    duplicate_bag.fold(table, 0, fn(count, _, _) { count + 1 }),
  )
  assert duplicate_bag.fold_results(table, 0, fn(count, entry) {
      case entry {
        Ok(_) -> count
        Error(_) -> count + 1
      }
    })
    == Ok(2)
  let assert Ok(Nil) = duplicate_bag.close(table)
  assert duplicate_bag.lookup(table, "long") == Error(slate.TableDoesNotExist)
  let assert Ok(table) =
    duplicate_bag.open(
      path,
      key_decoder: decode.failure("", "accepted key"),
      value_decoder: decode.int,
    )
  expect_decode_error(duplicate_bag.lookup(table, "valid"))
  let assert Ok(Nil) = duplicate_bag.close(table)
  test_helper.cleanup(path)
}

pub fn set_counter_malformed_objects_unchanged_test() -> Nil {
  let path = "test_counter_object_shape.dets"
  test_helper.cleanup(path)
  let objects = malformed_objects()
  let assert Ok(Nil) = write_raw_objects(path, Set, objects)
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  assert set.update_counter(table, "short", 1)
    == Error(set.CounterValueNotInteger)
  assert set.update_counter(table, "long", 1)
    == Error(set.CounterValueNotInteger)
  assert set.update_counter(table, "missing", 1)
    == Error(set.TableError(slate.NotFound))
  let assert Ok(Nil) = set.close(table)
  let assert Ok(stored) = read_raw_objects(path)
  assert list.length(stored) == 2
  list.each(objects, fn(object) {
    assert list.contains(stored, object)
  })
  let assert Ok(table) =
    set.open_with_access(
      path,
      slate.AutoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  list.each(["short", "long", "missing"], fn(key) {
    let assert Error(set.TableError(slate.AccessDenied(_))) =
      set.update_counter(table, key, 1)
    Nil
  })
  let assert Ok(Nil) = set.close(table)
  assert set.update_counter(table, "long", 1)
    == Error(set.TableError(slate.TableDoesNotExist))
  test_helper.cleanup(path)
}
