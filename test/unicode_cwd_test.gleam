import gleam/bit_array
import gleam/dynamic/decode
import gleam/option.{Some}
import slate
import slate/bag
import slate/duplicate_bag
import slate/set

type Check {
  Info
  MissingReadOnly
  TypeMismatch
  ReadOnlyInsert
}

pub fn japanese_cwd_info_test() -> Nil {
  check_apis("日本", Info)
}

pub fn latin1_cwd_info_test() -> Nil {
  check_apis("café", Info)
}

pub fn japanese_cwd_missing_readonly_test() -> Nil {
  check_apis("日本", MissingReadOnly)
}

pub fn latin1_cwd_missing_readonly_test() -> Nil {
  check_apis("café", MissingReadOnly)
}

pub fn unicode_cwd_missing_parent_classification_test() -> Nil {
  use cwd <- in_directory("café_日本")
  let path = "missing_parent/absent.dets"
  assert set.with_table(
      path,
      slate.NoRepair,
      slate.ReadWrite,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(_) { Ok(Nil) },
    )
    == Error(
      slate.FileNotFound(slate.FileErrorContext(
        Some(cwd <> "/" <> path),
        "enoent",
      )),
    )
}

pub fn japanese_cwd_type_mismatch_test() -> Nil {
  check_apis("日本", TypeMismatch)
}

pub fn latin1_cwd_type_mismatch_test() -> Nil {
  check_apis("café", TypeMismatch)
}

pub fn japanese_cwd_readonly_insert_test() -> Nil {
  check_apis("日本", ReadOnlyInsert)
}

pub fn latin1_cwd_readonly_insert_test() -> Nil {
  check_apis("café", ReadOnlyInsert)
}

fn check_apis(directory: String, check: Check) -> Nil {
  // The helper restores VM-wide cwd even when a Gleam assertion raises.
  use cwd <- in_directory(directory)
  check_api(
    cwd,
    check,
    fn(path, access, callback) {
      set.with_table(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    set.info,
    set.insert,
    fn(path) {
      bag.with_table(
        path,
        slate.AutoRepair,
        slate.ReadWrite,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback: fn(_) { Ok(Nil) },
      )
    },
  )
  check_api(
    cwd,
    check,
    fn(path, access, callback) {
      bag.with_table(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    bag.info,
    bag.insert,
    fn(path) {
      duplicate_bag.with_table(
        path,
        slate.AutoRepair,
        slate.ReadWrite,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback: fn(_) { Ok(Nil) },
      )
    },
  )
  check_api(
    cwd,
    check,
    fn(path, access, callback) {
      duplicate_bag.with_table(
        path,
        slate.AutoRepair,
        access,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback:,
      )
    },
    duplicate_bag.info,
    duplicate_bag.insert,
    fn(path) {
      set.with_table(
        path,
        slate.AutoRepair,
        slate.ReadWrite,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback: fn(_) { Ok(Nil) },
      )
    },
  )
}

fn check_api(
  cwd: String,
  check: Check,
  with_table: fn(
    String,
    slate.AccessMode,
    fn(table) -> Result(Nil, slate.DetsError),
  ) -> Result(Nil, slate.DetsError),
  info: fn(table) -> Result(slate.TableInfo, slate.DetsError),
  insert: fn(table, String, Int) -> Result(Nil, slate.DetsError),
  open_other_type: fn(String) -> Result(Nil, slate.DetsError),
) -> Nil {
  let path = "table.dets"
  let expected_path = cwd <> "/" <> path
  case check {
    MissingReadOnly -> {
      assert with_table(path, slate.ReadOnly, fn(_) { Ok(Nil) })
        == Error(
          slate.FileNotFound(slate.FileErrorContext(
            Some(expected_path),
            "enoent",
          )),
        )
    }
    Info | TypeMismatch | ReadOnlyInsert -> {
      let assert Ok(Nil) =
        with_table(path, slate.ReadWrite, fn(table) {
          let assert Ok(Nil) = insert(table, "key", 1)
          case check {
            Info -> {
              let assert Ok(details) = info(table)
              assert bit_array.is_utf8(bit_array.from_string(details.file_path))
              assert details.file_path == expected_path
              assert details.object_count == 1
              assert details.file_size > 0
            }
            MissingReadOnly | TypeMismatch | ReadOnlyInsert -> Nil
          }
          Ok(Nil)
        })
      case check {
        TypeMismatch -> {
          assert open_other_type(path)
            == Error(
              slate.TypeMismatch(slate.FileErrorContext(
                Some(expected_path),
                "type_mismatch",
              )),
            )
        }
        ReadOnlyInsert -> {
          let assert Ok(Nil) =
            with_table(path, slate.ReadOnly, fn(table) {
              assert insert(table, "new", 2)
                == Error(
                  slate.AccessDenied(slate.FileErrorContext(
                    Some(expected_path),
                    "access_mode",
                  )),
                )
              Ok(Nil)
            })
          Nil
        }
        Info | MissingReadOnly -> Nil
      }
      let assert Ok(Nil) = delete_file(path)
      Nil
    }
  }
}

@external(erlang, "unicode_cwd_test_ffi", "in_directory")
fn in_directory(directory: String, callback: fn(String) -> a) -> a

type DeleteError

@external(erlang, "unicode_cwd_test_ffi", "delete_file")
fn delete_file(path: String) -> Result(Nil, DeleteError)
