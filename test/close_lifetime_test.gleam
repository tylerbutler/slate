//// A displaced table must keep its name while its old server is flushing,
//// even after OTP removes that name from its registry or its opener dies.

import gleam/dynamic/decode
import gleam/erlang/process.{type Monitor, type Pid, type Subject}
import gleam/list
import slate/set

type SuspendedTable

type Breakpoint

type CloseMode {
  Orderly
  KilledCloser
  OwnerDeath
}

type Worker(a) {
  Worker(pid: Pid, monitor: Monitor, result: Subject(a))
}

pub fn displaced_table_close_and_reopen_test() -> Nil {
  check_close_lifetime(Orderly)
}

pub fn displaced_table_killed_closer_test() -> Nil {
  check_close_lifetime(KilledCloser)
}

pub fn displaced_table_ordinary_owner_death_test() -> Nil {
  check_close_lifetime(OwnerDeath)
}

pub fn registry_loss_fails_closed_but_allows_cleanup_test() -> Nil {
  registry_failure()
}

pub fn death_before_native_open_releases_reservation_test() -> Nil {
  use _, path <- with_collision_paths
  with_native_open_breakpoint(fn(breakpoint) {
    let owner =
      start(fn() {
        set.open(path, key_decoder: decode.string, value_decoder: decode.int)
      })
    await_paused(breakpoint, owner.pid, 1000)
    assert reserved(path)
    disable_breakpoint(breakpoint)
    process.kill(owner.pid)
    assert await_down(owner) == process.Killed
    await_released(path)
  })
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let assert Ok(Nil) = set.close(table)
  await_released(path)
}

pub fn death_before_open_result_registration_test() -> Nil {
  use foreign_path, path <- with_collision_paths
  let assert Ok(foreign) =
    set.open(
      foreign_path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  with_opened_breakpoint(fn(breakpoint) {
    let owner =
      start(fn() {
        set.open(path, key_decoder: decode.string, value_decoder: decode.int)
      })
    // DETS has opened and linked its user, but Slate has not received a
    // lifetime PID yet. The pre-open reservation must cover this exact gap.
    await_paused(breakpoint, owner.pid, 1000)
    with_suspended_path(path, fn(suspended) {
      let assert Ok(Nil) = set.close(foreign)
      await_released(foreign_path)
      disable_breakpoint(breakpoint)
      process.kill(owner.pid)
      assert await_down(owner) == process.Killed
      await_unregistered(suspended)
      let next =
        start(fn() {
          let assert Ok(table) =
            set.open(
              path,
              key_decoder: decode.string,
              value_decoder: decode.int,
            )
          let assert Ok(Nil) = set.insert(table, "base", 2)
          set.close(table)
        })
      await_queued_open(suspended, next.pid)
      assert process.receive(next.result, 0) == Error(Nil)
      resume(suspended)
      assert finish(next) == Ok(Nil)
    })
  })
  await_released(path)
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  assert set.lookup(table, "base") == Ok(2)
  let assert Ok(Nil) = set.close(table)
  await_released(path)
}

pub fn owner_exit_after_abandoned_open_fence_test() -> Nil {
  use foreign_path, path <- with_collision_paths
  let assert Ok(foreign) =
    set.open(
      foreign_path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  with_opened_breakpoint(fn(open_breakpoint) {
    let owner =
      start(fn() {
        set.open(path, key_decoder: decode.string, value_decoder: decode.int)
      })
    await_paused(open_breakpoint, owner.pid, 1000)
    with_suspended_path(path, fn(suspended) {
      let assert Ok(Nil) = set.close(foreign)
      await_released(foreign_path)
      disable_breakpoint(open_breakpoint)
      with_lifetime_fence_breakpoint(fn(fence_breakpoint) {
        with_delayed_owner_exit(owner.pid, fn(release_exit) {
          assert await_down(owner) == process.Killed
          let fence = await_fence(fence_breakpoint, 1000)
          // The non-owner fence already returned, but OTP still lists the
          // dead opener. Now remove the name while its PID cannot flush.
          release_exit()
          await_unregistered(suspended)
          disable_breakpoint(fence_breakpoint)
          let assert Ok(Nil) = continue_open(fence)
          // A second fence must drain that newly pending close. An absent
          // registry entry alone must never release this reservation.
          await_queued_fence(suspended, fence)
          assert reserved(path)
          let next =
            start(fn() {
              let assert Ok(table) =
                set.open(
                  path,
                  key_decoder: decode.string,
                  value_decoder: decode.int,
                )
              let assert Ok(Nil) = set.insert(table, "base", 2)
              set.close(table)
            })
          await_queued_open(suspended, next.pid)
          resume(suspended)
          assert finish(next) == Ok(Nil)
        })
      })
    })
  })
  await_released(path)
  let assert Ok(table) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  assert set.lookup(table, "base") == Ok(2)
  let assert Ok(Nil) = set.close(table)
  await_released(path)
}

pub fn stale_shared_opener_fence_preserves_replacement_lifetime_test() -> Nil {
  use foreign_path, path <- with_collision_paths
  let assert Ok(foreign) =
    set.open(
      foreign_path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let assert Ok(original) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  let original_pid = track_table(original)
  assert different_names(foreign, original)
  let assert Ok(Nil) = set.insert(original, "base", 1)

  with_opened_breakpoint(fn(open_breakpoint) {
    let shared =
      start(fn() {
        set.open(path, key_decoder: decode.string, value_decoder: decode.int)
      })
    await_paused(open_breakpoint, shared.pid, 1000)
    disable_breakpoint(open_breakpoint)
    with_fence_result_breakpoint(fn(fence_breakpoint) {
      process.kill(shared.pid)
      assert await_down(shared) == process.Killed
      // The fence has captured the original PID but has not reported it.
      let fence = await_fence(fence_breakpoint, 1000)
      let assert Ok(Nil) = set.close(original)
      assert !process.is_alive(original_pid)
      let opened = process.new_subject()
      let replacement =
        start(fn() {
          let close_now = process.new_subject()
          let assert Ok(table) =
            set.open(
              path,
              key_decoder: decode.string,
              value_decoder: decode.int,
            )
          let assert Ok(Nil) = set.sync(table)
          let assert Ok(Nil) = set.insert(table, "base", 2)
          process.send(opened, #(table, close_now))
          let assert Ok(Nil) = process.receive(close_now, 10_000)
          set.close(table)
        })
      let assert Ok(#(table, close_now)) = process.receive(opened, 5000)
      let replacement_pid = track_table(table)
      assert !different_names(original, table)
      assert replacement_pid != original_pid
      assert process.is_alive(replacement_pid)
      assert registry_tracks(table)

      // Deliver the old, now-dead PID after the replacement is registered.
      disable_breakpoint(fence_breakpoint)
      let assert Ok(Nil) = continue_open(fence)
      await_fence_completion(path)
      assert registry_tracks(table)
        as "stale fence discarded the replacement monitor"
      assert reserved(path)
      assert process.is_alive(replacement_pid)
      let assert Ok(Nil) = set.close(foreign)
      await_released(foreign_path)

      with_suspended_table(table, fn(suspended) {
        process.send(close_now, Nil)
        await_unregistered(suspended)
        // Remove the caller-held gate: the retained replacement lifetime,
        // not a surviving close caller, must now prevent the earlier-slot open.
        process.kill(replacement.pid)
        assert await_down(replacement) == process.Killed
        let next =
          start(fn() {
            let assert Ok(reopened) =
              set.open(
                path,
                key_decoder: decode.string,
                value_decoder: decode.int,
              )
            assert set.lookup(reopened, "base") == Ok(2)
            let assert Ok(Nil) = set.insert(reopened, "base", 3)
            set.close(reopened)
          })
        await_old_server_monitor(suspended, next.pid)
        assert process.receive(next.result, 0) == Error(Nil)
        assert reserved(path)
        resume(suspended)
        assert finish(next) == Ok(Nil)
      })
    })
  })
  await_released(path)
  let assert Ok(reopened) =
    set.open(path, key_decoder: decode.string, value_decoder: decode.int)
  assert set.lookup(reopened, "base") == Ok(3)
  let assert Ok(Nil) = set.close(reopened)
  await_released(path)
}

fn check_close_lifetime(mode: CloseMode) -> Nil {
  use foreign_path, shared_path <- with_collision_paths
  let assert Ok(foreign) =
    set.open(
      foreign_path,
      key_decoder: decode.string,
      value_decoder: decode.int,
    )
  let opened = process.new_subject()
  let owner =
    start(fn() {
      let close_now = process.new_subject()
      let assert Ok(table) =
        set.open(
          shared_path,
          key_decoder: decode.string,
          value_decoder: decode.int,
        )
      let assert Ok(Nil) = set.insert(table, "base", 0)
      let assert Ok(Nil) = set.sync(table)
      // Leave a real dirty update for the suspended final close to flush.
      let assert Ok(Nil) = set.insert(table, "base", 1)
      process.send(opened, #(table, close_now))
      let assert Ok(Nil) = process.receive(close_now, 10_000)
      set.close(table)
    })
  let assert Ok(#(old_table, close_now)) = process.receive(opened, 5000)
  // Q occupied N, so P is displaced to N+1. Make N free again.
  assert different_names(foreign, old_table)
  let assert Ok(Nil) = set.close(foreign)
  await_released(foreign_path)

  with_suspended_table(old_table, fn(suspended) {
    case mode {
      Orderly | KilledCloser -> process.send(close_now, Nil)
      OwnerDeath -> process.kill(owner.pid)
    }
    // The old PID is still alive and cannot flush yet, but DETS has already
    // removed its registry entry. A rescan-only allocator would choose N.
    await_unregistered(suspended)
    // Lifetime tracking must not turn a blocked close into a node-wide gate.
    let assert Ok(independent) =
      set.open(
        foreign_path,
        key_decoder: decode.string,
        value_decoder: decode.int,
      )
    let assert Ok(Nil) = set.insert(independent, "independent", 9)
    let assert Ok(Nil) = set.close(independent)
    await_released(foreign_path)
    case mode {
      Orderly -> Nil
      KilledCloser -> {
        process.kill(owner.pid)
        assert await_down(owner) == process.Killed
      }
      OwnerDeath -> {
        assert await_down(owner) == process.Killed
      }
    }
    let next =
      start(fn() {
        let assert Ok(table) =
          set.open(
            shared_path,
            key_decoder: decode.string,
            value_decoder: decode.int,
          )
        let assert Ok(1) = set.lookup(table, "base")
        let assert Ok(Nil) = set.insert(table, "base", 2)
        set.close(table)
      })
    case mode {
      Orderly -> await_coordination(next.pid)
      KilledCloser | OwnerDeath -> await_old_server_monitor(suspended, next.pid)
    }
    assert process.receive(next.result, 0) == Error(Nil)
    resume(suspended)
    case mode {
      Orderly -> {
        assert finish(owner) == Ok(Nil)
      }
      KilledCloser | OwnerDeath -> Nil
    }
    assert finish(next) == Ok(Nil)
  })

  // The acknowledged write from the new owner must survive BOTH closes.
  let assert Ok(reopened) =
    set.open(shared_path, key_decoder: decode.string, value_decoder: decode.int)
  assert set.lookup(reopened, "base") == Ok(2)
  let assert Ok(Nil) = set.close(reopened)
  await_released(shared_path)
}

fn start(work: fn() -> a) -> Worker(a) {
  let ready = process.new_subject()
  let result = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let permission = process.new_subject()
      process.send(ready, permission)
      let assert Ok(Nil) = process.receive(permission, 10_000)
      process.send(result, work())
    })
  let assert Ok(permission) = process.receive(ready, 1000)
  let monitor = process.monitor(pid)
  track_worker(pid)
  process.send(permission, Nil)
  Worker(pid, monitor, result)
}

fn finish(worker: Worker(a)) -> a {
  let assert Ok(result) = process.receive(worker.result, 5000)
  assert await_down(worker) == process.Normal
  result
}

fn await_down(worker: Worker(a)) -> process.ExitReason {
  let down =
    process.new_selector()
    |> process.select_specific_monitor(worker.monitor, fn(down) { down })
    |> process.selector_receive(5000)
  process.demonitor_process(worker.monitor)
  let assert Ok(process.ProcessDown(_, _, reason)) = down
  reason
}

fn await_paused(breakpoint: Breakpoint, pid: Pid, remaining: Int) -> Nil {
  assert remaining > 0 as "opener did not reach the lifetime breakpoint"
  case list.contains(paused_workers(breakpoint), pid) {
    True -> Nil
    False -> {
      process.sleep(1)
      await_paused(breakpoint, pid, remaining - 1)
    }
  }
}

fn await_fence(breakpoint: Breakpoint, remaining: Int) -> Pid {
  assert remaining > 0 as "cleanup worker did not reach the fence breakpoint"
  case paused_workers(breakpoint) {
    [pid] -> pid
    _ -> {
      process.sleep(1)
      await_fence(breakpoint, remaining - 1)
    }
  }
}

@external(erlang, "close_lifetime_test_ffi", "with_collision_paths")
fn with_collision_paths(callback: fn(String, String) -> a) -> a

@external(erlang, "close_lifetime_test_ffi", "with_suspended_table")
fn with_suspended_table(
  table: set.Set(String, Int),
  callback: fn(SuspendedTable) -> a,
) -> a

@external(erlang, "close_lifetime_test_ffi", "resume")
fn resume(table: SuspendedTable) -> Nil

@external(erlang, "close_lifetime_test_ffi", "await_unregistered")
fn await_unregistered(table: SuspendedTable) -> Nil

@external(erlang, "close_lifetime_test_ffi", "await_queued_open")
fn await_queued_open(table: SuspendedTable, opener: Pid) -> Nil

@external(erlang, "close_lifetime_test_ffi", "await_queued_fence")
fn await_queued_fence(table: SuspendedTable, worker: Pid) -> Nil

@external(erlang, "close_lifetime_test_ffi", "with_delayed_owner_exit")
fn with_delayed_owner_exit(owner: Pid, callback: fn(fn() -> Nil) -> a) -> a

@external(erlang, "close_lifetime_test_ffi", "await_old_server_monitor")
fn await_old_server_monitor(table: SuspendedTable, opener: Pid) -> Nil

@external(erlang, "close_lifetime_test_ffi", "different_names")
fn different_names(first: set.Set(k, v), second: set.Set(k, v)) -> Bool

@external(erlang, "close_lifetime_test_ffi", "await_released")
fn await_released(path: String) -> Nil

@external(erlang, "table_name_race_test_ffi", "await_coordination")
fn await_coordination(pid: Pid) -> Nil

@external(erlang, "close_lifetime_test_ffi", "with_suspended_path")
fn with_suspended_path(path: String, callback: fn(SuspendedTable) -> a) -> a

@external(erlang, "close_lifetime_test_ffi", "reserved")
fn reserved(path: String) -> Bool

@external(erlang, "close_lifetime_test_ffi", "registry_failure")
fn registry_failure() -> Nil

@external(erlang, "table_name_race_test_ffi", "with_opened_breakpoint")
fn with_opened_breakpoint(callback: fn(Breakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "with_native_open_breakpoint")
fn with_native_open_breakpoint(callback: fn(Breakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "with_lifetime_fence_breakpoint")
fn with_lifetime_fence_breakpoint(callback: fn(Breakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "with_fence_result_breakpoint")
fn with_fence_result_breakpoint(callback: fn(Breakpoint) -> a) -> a

@external(erlang, "table_name_race_test_ffi", "continue_open")
fn continue_open(pid: Pid) -> Result(Nil, Nil)

@external(erlang, "table_name_race_test_ffi", "paused_openers")
fn paused_workers(breakpoint: Breakpoint) -> List(Pid)

@external(erlang, "table_name_race_test_ffi", "disable_open_breakpoint")
fn disable_breakpoint(breakpoint: Breakpoint) -> Nil

@external(erlang, "close_lifetime_test_ffi", "track_worker")
fn track_worker(pid: Pid) -> Nil

@external(erlang, "close_lifetime_test_ffi", "track_table")
fn track_table(table: set.Set(k, v)) -> Pid

@external(erlang, "close_lifetime_test_ffi", "await_fence_completion")
fn await_fence_completion(path: String) -> Nil

@external(erlang, "close_lifetime_test_ffi", "registry_tracks")
fn registry_tracks(table: set.Set(k, v)) -> Bool
