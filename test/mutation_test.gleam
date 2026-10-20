//// Public API mutation ordering, with real OTP breakpoints after validation.

import gleam/dynamic/decode
import gleam/erlang/process.{type Monitor, type Pid, type Subject}
import gleam/list
import slate
import slate/bag
import slate/exclusive
import slate/set
import test_helper

type Breakpoint

type Worker(a) {
  Worker(pid: Pid, monitor: Monitor, completed: Subject(a))
}

pub fn concurrent_integer_increments_test() -> Nil {
  let path = "test_mutation_increments.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "hits", 0)
  let workers =
    list.map(test_helper.range(1, 8), fn(_) {
      start(fn() {
        list.each(test_helper.range(1, 100), fn(_) {
          let assert Ok(_) = set.update_counter(table, "hits", 1)
        })
      })
    })
  list.each(workers, fn(worker) {
    assert finish(worker) == Nil
  })
  assert set.lookup(table, "hits") == Ok(800)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

pub fn all_set_mutations_wait_for_counter_test() -> Nil {
  let operations = [
    #(fn(table) { set.insert(table, "hits", 9) }, Ok(Nil)),
    #(fn(table) { set.insert_list(table, [#("hits", 9)]) }, Ok(Nil)),
    #(
      fn(table) { set.insert_new(table, "hits", 9) },
      Error(slate.KeyAlreadyPresent),
    ),
    #(fn(table) { set.delete_key(table, "hits") }, Ok(Nil)),
    #(fn(table) { set.delete_object(table, "hits", 1) }, Ok(Nil)),
    #(set.delete_all, Ok(Nil)),
    #(set.close, Error(slate.UnexpectedError("not_owner"))),
  ]
  list.each(operations, fn(operation) {
    let #(mutate, expected) = operation
    with_counter_breakpoint(fn(breakpoint) {
      let path = "test_mutation_gate.dets"
      let assert Ok(table) =
        set.open(path, key_decoder: decode.string, value_decoder: decode.int)
      let assert Ok(Nil) = set.insert(table, "hits", 0)
      let counter = start(fn() { set.update_counter(table, "hits", 1) })
      await_paused(breakpoint, counter.pid, 1000)
      let writer = start(fn() { mutate(table) })
      await_coordination(writer.pid)
      // Reads remain outside the mutation gate.
      assert set.lookup(table, "hits") == Ok(0)
      assert process.receive(writer.completed, 0) == Error(Nil)
      disable_breakpoint(breakpoint)
      let assert Ok(Nil) = continue_worker(counter.pid)
      assert finish(counter) == Ok(1)
      assert finish(writer) == expected
      // Only the original opener can close its DETS ownership.
      assert set.close(table) == Ok(Nil)
      test_helper.cleanup(path)
    })
  })
}

pub fn owner_close_waits_for_counter_test() -> Nil {
  with_counter_breakpoint(fn(breakpoint) {
    let path = "test_mutation_owner_close.dets"
    let opened = process.new_subject()
    let owner =
      start(fn() {
        let close_now = process.new_subject()
        let assert Ok(table) =
          set.open(path, key_decoder: decode.string, value_decoder: decode.int)
        let assert Ok(Nil) = set.insert(table, "hits", 0)
        process.send(opened, #(table, close_now))
        let assert Ok(Nil) = process.receive(close_now, 5000)
        set.close(table)
      })
    let assert Ok(#(table, close_now)) = process.receive(opened, 5000)
    let counter = start(fn() { set.update_counter(table, "hits", 1) })
    await_paused(breakpoint, counter.pid, 1000)
    process.send(close_now, Nil)
    await_coordination(owner.pid)
    disable_breakpoint(breakpoint)
    let assert Ok(Nil) = continue_worker(counter.pid)
    assert finish(counter) == Ok(1)
    assert finish(owner) == Ok(Nil)
    assert set.lookup(table, "hits") == Error(slate.TableDoesNotExist)
    test_helper.cleanup(path)
  })
}

pub fn type_changing_writer_waits_for_validation_test() -> Nil {
  with_counter_breakpoint(fn(breakpoint) {
    let path = "test_mutation_float_writer.dets"
    let assert Ok(counter_table) =
      set.open(path, key_decoder: decode.string, value_decoder: decode.int)
    let assert Ok(float_table) =
      set.open(path, key_decoder: decode.string, value_decoder: decode.float)
    let assert Ok(Nil) = set.insert(counter_table, "hits", 0)
    let counter = start(fn() { set.update_counter(counter_table, "hits", 1) })
    await_paused(breakpoint, counter.pid, 1000)
    let writer = start(fn() { set.insert(float_table, "hits", 1.5) })
    await_coordination(writer.pid)
    disable_breakpoint(breakpoint)
    let assert Ok(Nil) = continue_worker(counter.pid)
    assert finish(counter) == Ok(1)
    assert finish(writer) == Ok(Nil)
    assert set.update_counter(counter_table, "hits", 1)
      == Error(set.CounterValueNotInteger)
    assert set.lookup(float_table, "hits") == Ok(1.5)
    let assert Ok(Nil) = set.close(float_table)
    let assert Ok(Nil) = set.close(counter_table)
    test_helper.cleanup(path)
  })
}

pub fn counter_holder_death_and_independent_table_test() -> Nil {
  with_counter_breakpoint(fn(breakpoint) {
    let path = "test_mutation_death.dets"
    let independent_path = "test_mutation_independent.dets"
    let assert Ok(table) =
      set.open(path, key_decoder: decode.string, value_decoder: decode.int)
    let assert Ok(independent) =
      set.open(
        independent_path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    let assert Ok(Nil) = set.insert(table, "hits", 0)
    let holder = start(fn() { set.update_counter(table, "hits", 1) })
    await_paused(breakpoint, holder.pid, 1000)
    let writer = start(fn() { set.delete_key(table, "hits") })
    await_coordination(writer.pid)
    // A different table is writable while this counter holds its gate.
    assert set.insert(independent, "hits", 10) == Ok(Nil)
    disable_breakpoint(breakpoint)
    assert set.update_counter(independent, "hits", 1) == Ok(11)
    process.kill(holder.pid)
    let assert process.Killed = await_down(holder)
    assert finish(writer) == Ok(Nil)
    assert set.update_counter(table, "hits", 1)
      == Error(set.TableError(slate.NotFound))
    assert set.insert(table, "hits", 5) == Ok(Nil)
    assert set.update_counter(table, "hits", 1) == Ok(6)
    let assert Ok(Nil) = set.close(table)
    let assert Ok(Nil) = set.close(independent)
    test_helper.cleanup(path)
    test_helper.cleanup(independent_path)
  })
}

pub fn bag_insert_new_uses_guarded_insert_test() -> Nil {
  with_insert_breakpoint(fn(breakpoint) {
    let path = "test_mutation_bag.dets"
    let assert Ok(table) =
      bag.open(path, key_decoder: decode.string, value_decoder: decode.int)
    let first = start(fn() { bag.insert(table, "key", 1) })
    await_paused(breakpoint, first.pid, 1000)
    let second = start(fn() { bag.insert_new(table, "key", 2) })
    await_coordination(second.pid)
    assert paused_workers(breakpoint) == [first.pid]
    disable_breakpoint(breakpoint)
    let assert Ok(Nil) = continue_worker(first.pid)
    assert finish(first) == Ok(Nil)
    assert finish(second) == Ok(Nil)
    assert bag.size(table) == Ok(2)
    assert bag.insert_new(table, "key", 2) == Error(slate.KeyAlreadyPresent)
    let assert Ok(Nil) = bag.close(table)
    test_helper.cleanup(path)
  })
}

pub fn exclusive_and_ordinary_mutations_share_gate_test() -> Nil {
  let path = "test_mutation_exclusive.dets"
  let assert Ok(Nil) =
    set.with_exclusive_table(
      path,
      slate.NoRepair,
      slate.ReadWrite,
      exclusive.Immediate,
      decode.string,
      decode.int,
      fn(exclusive_table) {
        // Deliberately mix handles to verify internal identity normalization;
        // applications must still follow the exclusive participation contract.
        let assert Ok(ordinary_table) =
          set.open(path, key_decoder: decode.string, value_decoder: decode.int)
        let assert Ok(Nil) = set.insert(exclusive_table, "hits", 0)
        with_counter_breakpoint(fn(breakpoint) {
          let counter =
            start(fn() { set.update_counter(exclusive_table, "hits", 1) })
          await_paused(breakpoint, counter.pid, 1000)
          let writer = start(fn() { set.insert(ordinary_table, "hits", 9) })
          await_coordination(writer.pid)
          disable_breakpoint(breakpoint)
          let assert Ok(Nil) = continue_worker(counter.pid)
          assert finish(counter) == Ok(1)
          assert finish(writer) == Ok(Nil)
        })
        assert set.lookup(exclusive_table, "hits") == Ok(9)
        set.close(ordinary_table)
      },
    )
  test_helper.cleanup(path)
  test_helper.cleanup(path <> ".slate.lock")
}

pub fn fold_callback_can_mutate_test() -> Nil {
  let path = "test_mutation_callback.dets"
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.insert(table, "hits", 0)
  // Run a different process's write from the callback to detect a held gate,
  // rather than relying on global's same-requester reentrancy.
  assert set.fold(table, 0, fn(total, key, _) {
      let worker = start(fn() { set.update_counter(table, key, 1) })
      assert finish(worker) == Ok(1)
      total + 1
    })
    == Ok(1)
  let assert Ok(Nil) = set.close(table)
  test_helper.cleanup(path)
}

fn start(work: fn() -> a) -> Worker(a) {
  start_after(work, fn() { Nil })
}

pub fn worker_waits_for_monitor_before_starting_test() -> Nil {
  let began = process.new_subject()
  let worker =
    start_after(
      fn() {
        process.send(began, Nil)
        42
      },
      fn() {
        // Deliberately leave the child alive but not yet monitored. Even
        // instantaneous work must wait for the parent's permission.
        process.sleep(50)
        assert process.receive(began, 0) == Error(Nil)
      },
    )
  assert finish(worker) == 42
  assert process.receive(began, 0) == Ok(Nil)
}

fn start_after(work: fn() -> a, before_monitor: fn() -> Nil) -> Worker(a) {
  let ready = process.new_subject()
  let completed = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let permission = process.new_subject()
      process.send(ready, permission)
      let assert Ok(Nil) = process.receive(permission, 10_000)
      process.send(completed, work())
    })
  let assert Ok(permission) = process.receive(ready, 1000)
  before_monitor()
  let monitor = process.monitor(pid)
  process.send(permission, Nil)
  Worker(pid, monitor, completed)
}

fn finish(worker: Worker(a)) -> a {
  let assert Ok(value) = process.receive(worker.completed, 10_000)
  let assert process.Normal = await_down(worker)
  value
}

fn await_down(worker: Worker(a)) -> process.ExitReason {
  let down =
    process.new_selector()
    |> process.select_specific_monitor(worker.monitor, fn(down) { down })
    |> process.selector_receive(1000)
  process.demonitor_process(worker.monitor)
  let assert Ok(process.ProcessDown(_, _, reason)) = down
  reason
}

fn await_paused(breakpoint: Breakpoint, pid: Pid, remaining: Int) -> Nil {
  assert remaining > 0 as "mutation did not reach DETS breakpoint"
  case list.contains(paused_workers(breakpoint), pid) {
    True -> Nil
    False -> {
      process.sleep(1)
      await_paused(breakpoint, pid, remaining - 1)
    }
  }
}

@external(erlang, "table_name_race_test_ffi", "with_counter_breakpoint")
fn with_counter_breakpoint(callback: fn(Breakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "with_insert_breakpoint")
fn with_insert_breakpoint(callback: fn(Breakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "paused_openers")
fn paused_workers(breakpoint: Breakpoint) -> List(Pid)

@external(erlang, "table_name_race_test_ffi", "continue_open")
fn continue_worker(pid: Pid) -> Result(Nil, Nil)

@external(erlang, "table_name_race_test_ffi", "disable_open_breakpoint")
fn disable_breakpoint(breakpoint: Breakpoint) -> Nil

@external(erlang, "table_name_race_test_ffi", "await_coordination")
fn await_coordination(pid: Pid) -> Nil
