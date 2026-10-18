//// Deterministic allocation races through the public Gleam APIs.
//// Both callers select the same free pool slot, then the first opens while
//// the second is stopped at the real DETS call. Tables stay open until results
//// and independent contents have been checked.

import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process.{type Monitor, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import slate
import slate/bag
import slate/exclusive
import slate/set
import test_helper

type OpenBreakpoint

type FilenameEncoding {
  LegacyBytes
  Unicode
}

type Worker {
  Worker(pid: Pid, monitor: Monitor, commands: Subject(Nil))
}

type Opened {
  Opened(path: String, table: set.Set(String, Int))
}

/// Ordinary opens must reallocate when another path wins their selected name.
pub fn ordinary_colliding_opens_test() -> Nil {
  with_open_breakpoint(fn(breakpoint) {
    let #(first_path, second_path) =
      colliding_paths("test_race_ordinary_", LegacyBytes)
    let opened = process.new_subject()
    let completed = process.new_subject()
    let first = start_ordinary(first_path, 11, opened, completed)
    let first_opener = await_paused(breakpoint, [], 1000)
    let second = start_ordinary(second_path, 22, opened, completed)
    let second_opener = await_paused(breakpoint, [first_opener], 1000)

    let assert Ok(Nil) = continue_open(first_opener)
    let first_result = process.receive(opened, 5000)
    let assert Ok(Nil) = continue_open(second_opener)
    // The retry passes the same breakpoint; disable it before waiting.
    disable_open_breakpoint(breakpoint)
    let second_result = process.receive(opened, 5000)

    // Always release both workers before asserting the regression results.
    process.send(first.commands, Nil)
    process.send(second.commands, Nil)
    let first_done = process.receive(completed, 5000)
    let second_done = process.receive(completed, 5000)
    await_worker(first)
    await_worker(second)
    test_helper.cleanup(first_path)
    test_helper.cleanup(second_path)

    let assert Ok(Ok(Opened(path: actual_first, ..))) = first_result
    let assert Ok(Ok(Opened(path: actual_second, ..))) = second_result
    assert actual_first == first_path
    assert actual_second == second_path
    assert first_done == Ok(Ok(Nil))
    assert second_done == Ok(Ok(Nil))
  })
}

/// Independent exclusive same-VM sessions share the allocator, including its
/// Unicode filenames and tagged table references.
pub fn exclusive_unicode_colliding_opens_test() -> Nil {
  with_open_breakpoint(fn(breakpoint) {
    let #(first_path, second_path) =
      colliding_paths("test_race_exclusive_caf\u{e9}_\u{1f4be}_", Unicode)
    let opened = process.new_subject()
    let completed = process.new_subject()
    let first = start_exclusive(first_path, 11, opened, completed)
    let first_opener = await_paused(breakpoint, [], 1000)
    let second = start_exclusive(second_path, 22, opened, completed)
    let second_opener = await_paused(breakpoint, [first_opener], 1000)

    let assert Ok(Nil) = continue_open(first_opener)
    let first_result = process.receive(opened, 5000)
    let assert Ok(Nil) = continue_open(second_opener)
    disable_open_breakpoint(breakpoint)
    let second_result = process.receive(opened, 1000)
    process.send(first.commands, Nil)
    process.send(second.commands, Nil)
    let first_done = process.receive(completed, 5000)
    let second_done = process.receive(completed, 5000)
    await_worker(first)
    await_worker(second)
    test_helper.cleanup(first_path)
    test_helper.cleanup(second_path)
    test_helper.cleanup(first_path <> ".slate.lock")
    test_helper.cleanup(second_path <> ".slate.lock")

    assert first_done == Ok(Ok(Nil))
    assert second_done == Ok(Ok(Nil))
    let assert Ok(actual_first) = first_result
    let assert Ok(actual_second) = second_result
    assert actual_first == first_path
    assert actual_second == second_path
  })
}

/// Duplicate opens and dot/parent aliases must find the same-path table after
/// a foreign collision, rather than attaching to the foreign table.
pub fn duplicate_same_path_collision_interleaving_test() -> Nil {
  with_open_breakpoint(fn(breakpoint) {
    let #(foreign_path, shared_path) =
      colliding_paths("test_race_shared_", LegacyBytes)
    let alias_path = "./unused/../" <> shared_path
    let opened = process.new_subject()
    let completed = process.new_subject()
    let foreign = start_ordinary(foreign_path, 11, opened, completed)
    let foreign_opener = await_paused(breakpoint, [], 1000)
    let first = start_ordinary(shared_path, 22, opened, completed)
    let first_opener = await_paused(breakpoint, [foreign_opener], 1000)
    let second = start_ordinary(alias_path, 22, opened, completed)
    let second_opener =
      await_paused(breakpoint, [foreign_opener, first_opener], 1000)

    let assert Ok(Nil) = continue_open(foreign_opener)
    let foreign_result = process.receive(opened, 5000)
    disable_open_breakpoint(breakpoint)
    let assert Ok(Nil) = continue_open(first_opener)
    let first_result = process.receive(opened, 5000)
    let assert Ok(Nil) = continue_open(second_opener)
    let second_result = process.receive(opened, 5000)
    process.send(foreign.commands, Nil)
    process.send(first.commands, Nil)
    let foreign_done = process.receive(completed, 5000)
    let first_done = process.receive(completed, 5000)

    // The second opener keeps the shared table alive after the first closes.
    let assert Ok(Ok(Opened(table: second_table, ..))) = second_result
    assert set.lookup(second_table, "key") == Ok(22)
    process.send(second.commands, Nil)
    let second_done = process.receive(completed, 5000)
    await_worker(foreign)
    await_worker(first)
    await_worker(second)
    test_helper.cleanup(foreign_path)
    test_helper.cleanup(shared_path)

    let assert Ok(Ok(Opened(table: first_table, ..))) = first_result
    assert first_table == second_table
    let assert Ok(Ok(_)) = foreign_result
    assert foreign_done == Ok(Ok(Nil))
    assert first_done == Ok(Ok(Nil))
    assert second_done == Ok(Ok(Nil))
  })
}

/// Reallocation must not erase genuine conflicting access/type errors.
pub fn conflicting_options_after_collision_test() -> Nil {
  with_open_breakpoint(fn(breakpoint) {
    let #(foreign_path, shared_path) =
      colliding_paths("test_race_conflict_", LegacyBytes)
    let opened = process.new_subject()
    let completed = process.new_subject()
    let conflicts = process.new_subject()
    let foreign = start_ordinary(foreign_path, 11, opened, completed)
    let foreign_opener = await_paused(breakpoint, [], 1000)
    let shared = start_ordinary(shared_path, 22, opened, completed)
    let shared_opener = await_paused(breakpoint, [foreign_opener], 1000)
    let _reader =
      process.spawn(fn() {
        let result =
          set.open_with_access(
            shared_path,
            slate.AutoRepair,
            slate.ReadOnly,
            key_decoder: decode.string,
            value_decoder: decode.int,
          )
          |> result.try(set.close)
        process.send(conflicts, result)
      })
    let reader_opener =
      await_paused(breakpoint, [foreign_opener, shared_opener], 1000)

    let assert Ok(Nil) = continue_open(foreign_opener)
    let foreign_result = process.receive(opened, 5000)
    disable_open_breakpoint(breakpoint)
    let assert Ok(Nil) = continue_open(shared_opener)
    let shared_result = process.receive(opened, 5000)
    let assert Ok(Nil) = continue_open(reader_opener)
    let reader_result = process.receive(conflicts, 5000)
    let bag_result =
      bag.open(
        "./unused/../" <> shared_path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
      |> result.try(bag.close)
    process.send(foreign.commands, Nil)
    process.send(shared.commands, Nil)
    let foreign_done = process.receive(completed, 5000)
    let shared_done = process.receive(completed, 5000)
    await_worker(foreign)
    await_worker(shared)
    test_helper.cleanup(foreign_path)
    test_helper.cleanup(shared_path)

    let assert Ok(Ok(_)) = foreign_result
    let assert Ok(Ok(_)) = shared_result
    let expected =
      Error(
        slate.AlreadyOpen(slate.FileErrorContext(
          Some(charlist.to_string(canonical_bytes(shared_path))),
          "incompatible_arguments",
        )),
      )
    assert reader_result == Ok(expected)
    assert bag_result == expected
    assert foreign_done == Ok(Ok(Nil))
    assert shared_done == Ok(Ok(Nil))
  })
}

/// The winner can close between the incompatible_arguments reply and inspection.
pub fn collision_winner_closes_before_inspection_test() -> Nil {
  with_open_breakpoint(fn(breakpoint) {
    let #(first_path, second_path) =
      colliding_paths("test_race_close_", LegacyBytes)
    let opened = process.new_subject()
    let completed = process.new_subject()
    let first = start_ordinary(first_path, 11, opened, completed)
    let first_opener = await_paused(breakpoint, [], 1000)
    let second = start_ordinary(second_path, 22, opened, completed)
    let second_opener = await_paused(breakpoint, [first_opener], 1000)
    let assert Ok(Nil) = continue_open(first_opener)
    let first_result = process.receive(opened, 5000)
    let collision_breakpoint = collision_check_breakpoint(breakpoint)
    let assert Ok(Nil) = continue_open(second_opener)
    await_paused(collision_breakpoint, [], 1000)
    process.send(first.commands, Nil)
    let first_done = process.receive(completed, 5000)
    disable_open_breakpoint(collision_breakpoint)
    let assert Ok(Nil) = continue_open(second_opener)
    let second_result = process.receive(opened, 5000)
    process.send(second.commands, Nil)
    let second_done = process.receive(completed, 5000)
    await_worker(first)
    await_worker(second)
    test_helper.cleanup(first_path)
    test_helper.cleanup(second_path)

    let assert Ok(Ok(_)) = first_result
    let assert Ok(Ok(_)) = second_result
    assert first_done == Ok(Ok(Nil))
    assert second_done == Ok(Ok(Nil))
  })
}

fn start_ordinary(
  path: String,
  value: Int,
  opened: Subject(Result(Opened, slate.DetsError)),
  completed: Subject(Result(Nil, slate.DetsError)),
) -> Worker {
  let ready = process.new_subject()
  let pid =
    process.spawn(fn() {
      let commands = process.new_subject()
      process.send(ready, commands)
      let result =
        set.open(path, key_decoder: decode.string, value_decoder: decode.int)
      case result {
        Ok(table) -> {
          let assert Ok(Nil) = set.insert(table, "key", value)
          let assert Ok(info) = set.info(table)
          assert info.file_path == charlist.to_string(canonical_bytes(path))
        }
        Error(_) -> Nil
      }
      process.send(opened, case result {
        Ok(table) -> Ok(Opened(path, table))
        Error(error) -> Error(error)
      })
      let _ = process.receive(commands, 10_000)
      let outcome = case result {
        Ok(table) -> {
          let found = set.lookup(table, "key")
          let closed = set.close(table)
          assert found == Ok(value)
          closed
        }
        Error(error) -> Error(error)
      }
      process.send(completed, outcome)
    })
  let assert Ok(commands) = process.receive(ready, 1000)
  Worker(pid, process.monitor(pid), commands)
}

fn start_exclusive(
  path: String,
  value: Int,
  opened: Subject(String),
  completed: Subject(Result(Nil, exclusive.SessionError)),
) -> Worker {
  let ready = process.new_subject()
  let pid =
    process.spawn(fn() {
      let commands = process.new_subject()
      process.send(ready, commands)
      let result =
        set.with_exclusive_table(
          path:,
          repair: slate.NoRepair,
          access: slate.ReadWrite,
          wait: exclusive.Immediate,
          key_decoder: decode.string,
          value_decoder: decode.int,
          callback: fn(table) {
            let assert Ok(Nil) = set.insert(table, "key", value)
            let assert Ok(info) = set.info(table)
            assert info.file_path == canonical_unicode_string(path)
            process.send(opened, path)
            let _ = process.receive(commands, 10_000)
            assert set.lookup(table, "key") == Ok(value)
            Ok(Nil)
          },
        )
      process.send(completed, result)
    })
  let assert Ok(commands) = process.receive(ready, 1000)
  Worker(pid, process.monitor(pid), commands)
}

fn await_worker(worker: Worker) -> Nil {
  let down =
    process.new_selector()
    |> process.select_specific_monitor(worker.monitor, fn(down) { down })
    |> process.selector_receive(1000)
  process.demonitor_process(worker.monitor)
  let assert Ok(process.ProcessDown(_, pid, process.Normal)) = down
  assert pid == worker.pid
}

fn colliding_paths(
  prefix: String,
  encoding: FilenameEncoding,
) -> #(String, String) {
  find_collision(prefix, encoding, 0, dict.new())
}

fn find_collision(
  prefix: String,
  encoding: FilenameEncoding,
  index: Int,
  seen: dict.Dict(Int, String),
) -> #(String, String) {
  // Pigeonhole principle guarantees a collision within 4097 candidates.
  assert index <= 4096
  let path = prefix <> int.to_string(index) <> ".dets"
  let canonical = case encoding {
    LegacyBytes -> canonical_bytes(path)
    Unicode -> canonical_charlist(charlist.from_string(path))
  }
  let slot = path_hash(canonical, 4096)
  case dict.get(seen, slot) {
    Ok(previous) -> #(previous, path)
    Error(Nil) ->
      find_collision(prefix, encoding, index + 1, dict.insert(seen, slot, path))
  }
}

fn canonical_unicode_string(path: String) -> String {
  path
  |> charlist.from_string
  |> canonical_charlist
  |> charlist.to_string
}

fn await_paused(
  breakpoint: OpenBreakpoint,
  previous: List(Pid),
  remaining: Int,
) -> Pid {
  assert remaining > 0 as "opener did not reach DETS breakpoint"
  case
    paused_openers(breakpoint)
    |> list.find(fn(pid) { !list.contains(previous, pid) })
  {
    Ok(pid) -> pid
    Error(Nil) -> {
      process.sleep(1)
      await_paused(breakpoint, previous, remaining - 1)
    }
  }
}

@external(erlang, "table_name_race_test_ffi", "with_open_breakpoint")
fn with_open_breakpoint(callback: fn(OpenBreakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "paused_openers")
fn paused_openers(breakpoint: OpenBreakpoint) -> List(Pid)

@external(erlang, "table_name_race_test_ffi", "continue_open")
fn continue_open(pid: Pid) -> Result(Nil, Nil)

@external(erlang, "table_name_race_test_ffi", "disable_open_breakpoint")
fn disable_open_breakpoint(breakpoint: OpenBreakpoint) -> Nil

@external(erlang, "table_name_race_test_ffi", "collision_check_breakpoint")
fn collision_check_breakpoint(breakpoint: OpenBreakpoint) -> OpenBreakpoint

@external(erlang, "slate_dets_ffi", "canonicalize_path")
fn canonical_bytes(path: String) -> Charlist

@external(erlang, "slate_dets_ffi", "canonicalize_path")
fn canonical_charlist(path: Charlist) -> Charlist

@external(erlang, "erlang", "phash2")
fn path_hash(path: Charlist, pool_size: Int) -> Int
