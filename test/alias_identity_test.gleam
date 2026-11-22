import gleam/dynamic/decode
import gleam/erlang/process.{type Monitor, type Pid, type Subject}
import gleam/list
import slate
import slate/bag
import slate/set

type AliasKind {
  HardLink
  UncleanHardLink
  ExistingFileSymlink
  MissingFileSymlink
  ExistingDirectorySymlink
  MissingDirectorySymlink
  SymlinkParent
  ExistingCaseLeaf
  MissingCaseLeaf
  CaseParent
}

type Breakpoint

type Writer {
  Writer(pid: Pid, monitor: Monitor)
}

pub fn hard_link_writers_persist_test() -> Nil {
  check_alias(HardLink)
}

pub fn existing_file_symlink_test() -> Nil {
  check_alias(ExistingFileSymlink)
}

pub fn missing_file_symlink_test() -> Nil {
  check_alias(MissingFileSymlink)
}

pub fn existing_directory_symlink_test() -> Nil {
  check_alias(ExistingDirectorySymlink)
}

pub fn missing_directory_symlink_test() -> Nil {
  check_alias(MissingDirectorySymlink)
}

pub fn symlink_before_parent_segment_test() -> Nil {
  check_alias(SymlinkParent)
}

pub fn existing_case_leaf_test() -> Nil {
  check_alias(ExistingCaseLeaf)
}

pub fn missing_case_leaf_test() -> Nil {
  check_alias(MissingCaseLeaf)
}

pub fn case_parent_test() -> Nil {
  check_alias(CaseParent)
}

fn check_alias(kind: AliasKind) -> Nil {
  use first, second <- with_alias(kind)
  let assert Ok(first_table) = open(first)
  let assert Ok(second_table) = open(second)
  assert first_table == second_table
  let assert Ok(Nil) = set.insert(first_table, "first", 11)
  let assert Ok(Nil) = set.insert(second_table, "second", 22)
  let assert Error(slate.AlreadyOpen(_)) =
    bag.open(second, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.close(first_table)
  assert set.lookup(second_table, "first") == Ok(11)
  let assert Ok(Nil) = set.close(second_table)
  let assert Ok(reopened) = open(second)
  assert set.lookup(reopened, "first") == Ok(11)
  assert set.lookup(reopened, "second") == Ok(22)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn raw_dets_hard_link_discovery_test() -> Nil {
  raw_discovery(HardLink)
}

pub fn raw_dets_file_symlink_discovery_test() -> Nil {
  raw_discovery(ExistingFileSymlink)
}

pub fn raw_dets_directory_symlink_discovery_test() -> Nil {
  raw_discovery(ExistingDirectorySymlink)
}

fn raw_discovery(kind: AliasKind) -> Nil {
  use first, second <- with_alias(kind)
  use <- with_raw(second)
  let assert Ok(table) = open(first)
  let assert Ok(Nil) = set.insert(table, "raw", 7)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(reopened) = open(second)
  assert set.lookup(reopened, "raw") == Ok(7)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

pub fn repair_retains_old_and_new_inode_reservations_test() -> Nil {
  use first, old_alias <- with_alias(HardLink)
  check_repair(first, old_alias, slate.ForceRepair)
}

pub fn auto_repair_retains_old_inode_reservation_test() -> Nil {
  use first, old_alias <- with_alias(UncleanHardLink)
  let assert Error(slate.NeedsRepair(_)) =
    set.open_with(
      first,
      slate.NoRepair,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  check_repair(first, old_alias, slate.AutoRepair)
}

fn check_repair(
  first: String,
  old_alias: String,
  repair: slate.RepairPolicy,
) -> Nil {
  let assert Ok(table) =
    set.open_with(
      first,
      repair,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(Nil) = set.insert(table, "repaired", 42)
  let new_alias = first <> ".new"
  hard_link(first, new_alias)
  let assert Ok(shared) = open(new_alias)
  assert shared == table
  case replaced(first, old_alias) {
    True -> {
      let assert Error(slate.AlreadyOpen(_)) = open(old_alias)
      Nil
    }
    False -> {
      let assert Ok(old_shared) = open(old_alias)
      assert old_shared == table
      let assert Ok(Nil) = set.close(old_shared)
      Nil
    }
  }
  let assert Ok(Nil) = set.close(shared)
  let assert Ok(Nil) = set.close(table)
  let assert Ok(reopened) = open(new_alias)
  assert set.lookup(reopened, "repaired") == Ok(42)
  let assert Ok(Nil) = set.close(reopened)
  // The conservative old-inode reservation ends only after shutdown.
  let assert Ok(old_table) = open(old_alias)
  let assert Ok(Nil) = set.close(old_table)
  Nil
}

pub fn failed_alias_open_does_not_poison_reservation_test() -> Nil {
  use first, second <- with_alias(MissingFileSymlink)
  let assert Error(slate.FileNotFound(_)) =
    set.open_with_access(
      second,
      slate.NoRepair,
      slate.ReadOnly,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(table) = open(first)
  let assert Ok(alias_table) = open(second)
  assert table == alias_table
  let assert Ok(Nil) = set.close(alias_table)
  let assert Ok(Nil) = set.close(table)
  Nil
}

pub fn concurrent_first_creation_alias_test() -> Nil {
  concurrent_creation(MissingFileSymlink)
}

pub fn concurrent_case_leaf_creation_test() -> Nil {
  concurrent_creation(MissingCaseLeaf)
}

fn concurrent_creation(kind: AliasKind) -> Nil {
  use first, second <- with_alias(kind)
  use breakpoint <- with_open_breakpoint
  let opened = process.new_subject()
  let completed = process.new_subject()
  let first_writer = start_writer(first, "first", 11, opened, completed)
  await_paused(breakpoint, first_writer.pid, 1000)
  let second_writer = start_writer(second, "second", 22, opened, completed)
  await_coordination(second_writer.pid)
  assert paused_openers(breakpoint) == [first_writer.pid]
  assert process.receive(opened, 0) == Error(Nil)
  disable_breakpoint(breakpoint)
  let assert Ok(Nil) = continue_open(first_writer.pid)
  let assert Ok(#(table, first_commands)) = process.receive(opened, 5000)
  let assert Ok(#(alias_table, second_commands)) = process.receive(opened, 5000)
  assert alias_table == table
  process.send(first_commands, Nil)
  assert process.receive(completed, 5000) == Ok(Ok(Nil))
  assert set.lookup(alias_table, "first") == Ok(11)
  process.send(second_commands, Nil)
  assert process.receive(completed, 5000) == Ok(Ok(Nil))
  finish_writer(first_writer)
  finish_writer(second_writer)
  let assert Ok(reopened) = open(first)
  assert set.lookup(reopened, "first") == Ok(11)
  assert set.lookup(reopened, "second") == Ok(22)
  let assert Ok(Nil) = set.close(reopened)
  Nil
}

fn start_writer(
  path: String,
  key: String,
  value: Int,
  opened: Subject(#(set.Set(String, Int), Subject(Nil))),
  completed: Subject(Result(Nil, slate.DetsError)),
) -> Writer {
  let worker =
    process.spawn_unlinked(fn() {
      let commands = process.new_subject()
      let assert Ok(table) = open(path)
      let assert Ok(Nil) = set.insert(table, key, value)
      process.send(opened, #(table, commands))
      let assert Ok(Nil) = process.receive(commands, 5000)
      process.send(completed, set.close(table))
    })
  track_worker(worker)
  Writer(worker, process.monitor(worker))
}

fn finish_writer(writer: Writer) -> Nil {
  let assert Ok(process.ProcessDown(_, _, process.Normal)) =
    process.new_selector()
    |> process.select_specific_monitor(writer.monitor, fn(down) { down })
    |> process.selector_receive(5000)
  process.demonitor_process(writer.monitor)
  Nil
}

fn await_paused(breakpoint: Breakpoint, pid: Pid, remaining: Int) -> Nil {
  assert remaining > 0
  case list.contains(paused_openers(breakpoint), pid) {
    True -> Nil
    False -> {
      process.sleep(1)
      await_paused(breakpoint, pid, remaining - 1)
    }
  }
}

fn open(path: String) -> Result(set.Set(String, Int), slate.DetsError) {
  set.open(path, key_decoder: decode.string, value_decoder: decode.int)
}

@external(erlang, "alias_identity_test_ffi", "with_alias")
fn with_alias(kind: AliasKind, callback: fn(String, String) -> Nil) -> Nil

@external(erlang, "alias_identity_test_ffi", "hard_link")
fn hard_link(first: String, second: String) -> Nil

@external(erlang, "alias_identity_test_ffi", "replaced")
fn replaced(first: String, second: String) -> Bool

@external(erlang, "alias_identity_test_ffi", "with_raw")
fn with_raw(path: String, callback: fn() -> Nil) -> Nil

@external(erlang, "alias_identity_test_ffi", "track_worker")
fn track_worker(pid: Pid) -> Nil

@external(erlang, "table_name_race_test_ffi", "with_open_breakpoint")
fn with_open_breakpoint(callback: fn(Breakpoint) -> Nil) -> Nil

@external(erlang, "table_name_race_test_ffi", "paused_openers")
fn paused_openers(breakpoint: Breakpoint) -> List(Pid)

@external(erlang, "table_name_race_test_ffi", "continue_open")
fn continue_open(pid: Pid) -> Result(Nil, Nil)

@external(erlang, "table_name_race_test_ffi", "disable_open_breakpoint")
fn disable_breakpoint(breakpoint: Breakpoint) -> Nil

@external(erlang, "table_name_race_test_ffi", "await_coordination")
fn await_coordination(pid: Pid) -> Nil
