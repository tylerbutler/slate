import gleam/dynamic/decode
import slate
import slate/bag
import slate/duplicate_bag
import slate/exclusive
import slate/set

pub fn main() -> Nil {
  case missing_native() {
    True -> {
      let assert Error(exclusive.AcquisitionFailed(exclusive.NativeUnavailable(
        _,
      ))) =
        set.with_exclusive_table(
          "package-set.dets",
          repair: slate.NoRepair,
          access: slate.ReadWrite,
          wait: exclusive.Immediate,
          key_decoder: decode.string,
          value_decoder: decode.int,
          callback: fn(_) { panic as "missing native callback ran" },
        )
      let assert Ok(table) =
        set.open(
          "package-unlocked.dets",
          key_decoder: decode.string,
          value_decoder: decode.int,
        )
      let assert Ok(Nil) = set.close(table)
      Nil
    }
    False -> {
      let assert Ok(Nil) =
        set.with_exclusive_table(
          "package-set.dets",
          repair: slate.NoRepair,
          access: slate.ReadWrite,
          wait: exclusive.Immediate,
          key_decoder: decode.string,
          value_decoder: decode.int,
          callback: fn(table) { set.insert(table, "kept", 42) },
        )
      let assert Ok(42) =
        set.with_exclusive_table(
          "package-set.dets",
          repair: slate.NoRepair,
          access: slate.ReadOnly,
          wait: exclusive.WaitUpTo(1000),
          key_decoder: decode.string,
          value_decoder: decode.int,
          callback: fn(table) { set.lookup(table, "kept") },
        )
      let assert Ok(Nil) =
        bag.with_exclusive_table(
          "package-bag.dets",
          repair: slate.NoRepair,
          access: slate.ReadWrite,
          wait: exclusive.Immediate,
          key_decoder: decode.string,
          value_decoder: decode.int,
          callback: fn(table) { bag.insert(table, "kept", 42) },
        )
      let assert Ok(Nil) =
        duplicate_bag.with_exclusive_table(
          "package-duplicate-bag.dets",
          repair: slate.NoRepair,
          access: slate.ReadWrite,
          wait: exclusive.Immediate,
          key_decoder: decode.string,
          value_decoder: decode.int,
          callback: fn(table) { duplicate_bag.insert(table, "kept", 42) },
        )
      Nil
    }
  }
  passed()
}

@external(erlang, "exclusive_package_probe_ffi", "missing_native")
fn missing_native() -> Bool

@external(erlang, "exclusive_package_probe_ffi", "passed")
fn passed() -> Nil
