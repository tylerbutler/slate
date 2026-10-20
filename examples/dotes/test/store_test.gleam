import dotes/lifecycle
import dotes/store
import gleam/erlang/process
import gleam/list
import gleam/string
import simplifile
import slate
import slate/exclusive
import store_test_helper as helper

pub fn contention_and_reacquisition_test() {
  helper.contention(helper.directory())
}

pub fn busy_and_persistence_test() {
  let path = helper.directory()
  let assert Ok(client) = store.open_in(path)
  let assert Ok(1) = store.create_note(client, "title", "body")
  let assert Error(error) = store.open_in(path)
  assert error
    == store.Sessions([
      store.SessionIssue(
        store.Counter,
        exclusive.AcquisitionFailed(exclusive.Busy),
      ),
    ])
  assert string.contains(store.error_message(error), "store is in use")
  let assert Ok(Nil) = store.close(client)
  let assert Error(store.OwnerStopped(_)) = store.close(client)
  let assert Error(store.OwnerStopped(_)) = store.get_note(client, 1)
  let assert Ok(next) = store.open_in(path)
  let assert Ok(note) = store.get_note(next, 1)
  assert note.body == "body"
  let assert Ok(2) = store.create_note(next, "two", "next")
  let assert Ok(Nil) = store.close(next)
  helper.assert_no_protocol_leaks()
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
}

pub fn later_open_failure_unwinds_counter_test() {
  let path = helper.directory()
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  let assert Ok(Nil) = simplifile.write(path <> "/notes.dets", "not DETS")
  let assert Error(store.Sessions([
    store.SessionIssue(
      store.Notes,
      exclusive.SessionFailed(exclusive.OpenFailure(slate.NotADetsFile(_))),
    ),
  ])) = store.open_in(path)
  let assert Ok(Nil) = simplifile.delete(path <> "/notes.dets")
  // No retry: failed startup must have finished cleanup before its reply.
  let assert Ok(client) = store.open_in(path)
  let assert Ok(Nil) = store.close(client)
  helper.assert_no_protocol_leaks()
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
}

pub fn directory_failure_is_typed_test() {
  let path = helper.directory()
  let assert Ok(Nil) = simplifile.write(path, "not a directory")
  let assert Error(store.Directory(_)) = store.open_in(path)
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
}

pub fn missing_note_remains_not_found_test() {
  use client, _path <- helper.with_store
  assert store.get_note(client, 19) == Error(store.Storage(slate.NotFound))
  assert store.update_note(client, 19, "missing")
    == Error(store.Storage(slate.NotFound))
  assert store.delete_note(client, 19) == Error(store.Storage(slate.NotFound))
  assert store.toggle_tag(client, 19, "ghost")
    == Error(store.Storage(slate.NotFound))
  assert store.get_tags(client, 19) == Ok([])
  assert store.get_history(client, 19) == Ok([])
}

pub fn parent_lifetime_releases_store_test() {
  parent_lifetime(False)
}

pub fn killed_parent_releases_store_test() {
  parent_lifetime(True)
}

fn parent_lifetime(kill: Bool) {
  let path = helper.directory()
  let ready = process.new_subject()
  let parent =
    process.spawn_unlinked(fn() {
      let stop = process.new_subject()
      let assert Ok(client) = store.open_in(path)
      let assert Ok(1) = store.create_note(client, "title", "kept")
      process.send(ready, #(client, stop))
      process.receive_forever(stop)
    })
  let monitor = process.monitor(parent)
  let assert Ok(#(client, stop)) = process.receive(ready, 5000)
  case kill {
    True -> process.kill(parent)
    False -> process.send(stop, Nil)
  }
  let assert Ok(_) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(5000)
  process.demonitor_process(monitor)
  // Do not call close: only the parent monitor can end this store's lifetime.
  helper.await_stopped(client, 5000)
  let assert Ok(next) = store.open_in(path)
  let assert Ok(note) = store.get_note(next, 1)
  assert note.body == "kept"
  let assert Ok(Nil) = store.close(next)
  helper.assert_no_protocol_leaks()
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
}

pub fn calls_do_not_consume_unrelated_monitor_messages_test() {
  use client, _path <- helper.with_store
  let exit = process.new_subject()
  let child =
    process.spawn_unlinked(fn() {
      let stop = process.new_subject()
      process.send(exit, stop)
      process.receive_forever(stop)
    })
  let monitor = process.monitor(child)
  let assert Ok(stop) = process.receive(exit, 5000)
  process.send(stop, Nil)
  list.each(list.repeat(Nil, 20), fn(_) {
    assert store.get_note(client, 1) == Error(store.Storage(slate.NotFound))
  })
  let assert Ok(process.ProcessDown(_, _, process.Normal)) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(5000)
  process.demonitor_process(monitor)
  helper.assert_no_protocol_leaks()
}

pub fn fourth_open_failure_unwinds_all_earlier_scopes_test() {
  let path = helper.directory()
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  let assert Ok(Nil) = simplifile.write(path <> "/history.dets", "not DETS")
  let assert Error(store.Sessions([
    store.SessionIssue(
      store.History,
      exclusive.SessionFailed(exclusive.OpenFailure(slate.NotADetsFile(_))),
    ),
  ])) = store.open_in(path)
  let assert Ok(Nil) = simplifile.delete(path <> "/history.dets")
  let assert Ok(client) = store.open_in(path)
  let assert Ok(Nil) = store.close(client)
  let assert Ok(Nil) = simplifile.delete(path)
  helper.assert_no_protocol_leaks()
}

pub fn concurrent_operations_retain_all_acknowledged_bodies_test() {
  use client, _path <- helper.with_store
  let assert Ok(1) = store.create_note(client, "title", "original")
  let replies = process.new_subject()
  let bodies =
    list.repeat(Nil, 20)
    |> list.index_map(fn(_, i) { string.inspect(i) })
  list.each(bodies, fn(body) {
    process.spawn_unlinked(fn() {
      process.send(replies, store.update_note(client, 1, body))
    })
    Nil
  })
  list.each(bodies, fn(_) {
    let assert Ok(Ok(Nil)) = process.receive(replies, 5000)
    Nil
  })
  let assert Ok(current) = store.get_note(client, 1)
  let assert Ok(history) = store.get_history(client, 1)
  let retained = [current.body, ..list.map(history, fn(r) { r.body })]
  assert list.length(retained) == 21
  list.each(["original", ..bodies], fn(body) {
    assert list.count(retained, fn(saved) { saved == body }) == 1
  })
}

pub fn cleanup_attempts_all_scopes_and_retains_failures_test() {
  helper.run_case(helper.CleanupFailures, helper.directory())
}

pub fn nested_primary_and_cleanup_failures_survive_test() {
  helper.run_case(helper.NestedStartupFailure, helper.directory())
}

pub fn retry_after_tag_delete_failure_test() {
  helper.run_case(helper.RetryTags, helper.directory())
}

pub fn retry_after_history_delete_failure_test() {
  helper.run_case(helper.RetryHistory, helper.directory())
}

pub fn concurrent_updates_are_serialized_test() {
  helper.run_case(helper.SerialUpdates, helper.directory())
}

pub fn concurrent_update_delete_is_ordered_test() {
  helper.run_case(helper.UpdateThenDelete, helper.directory())
}

pub fn owner_death_during_request_test() {
  helper.run_case(helper.OwnerDiesDuringRequest, helper.directory())
}

pub fn owner_death_during_close_test() {
  helper.run_case(helper.OwnerDiesDuringClose, helper.directory())
}

pub fn owner_death_during_startup_test() {
  helper.run_case(helper.OwnerDiesDuringStartup, helper.directory())
}

pub fn native_unavailable_does_not_fall_back_test() {
  helper.run_case(helper.NativeUnavailable, helper.directory())
}

pub fn parent_death_during_cleanup_keeps_diagnostic_test() {
  helper.run_case(helper.ParentDiesDuringCleanup, helper.directory())
}

pub fn occupied_web_port_is_handled_and_store_closed_test() {
  helper.run_case(helper.WebBusy, helper.directory())
}

pub fn terminal_startup_exit_is_handled_and_store_closed_test() {
  helper.run_case(helper.TuiStartupExit, helper.directory())
}

pub fn web_runtime_exit_is_handled_and_store_closed_test() {
  helper.run_case(helper.WebRuntimeExit, helper.directory())
}

pub fn terminal_runtime_exit_is_handled_and_store_closed_test() {
  helper.run_case(helper.TuiRuntimeExit, helper.directory())
}

pub fn lifecycle_parent_exit_closes_application_and_store_test() {
  let path = helper.directory()
  let ready = process.new_subject()
  let parent =
    process.spawn_unlinked(fn() {
      lifecycle.run(path, fn(client) {
        let assert Ok(1) = store.create_note(client, "title", "kept")
        let child = process.spawn(fn() { process.sleep_forever() })
        process.send(ready, #(process.self(), child))
        Ok(child)
      })
    })
  let assert Ok(#(worker, child)) = process.receive(ready, 5000)
  let worker_monitor = process.monitor(worker)
  let child_monitor = process.monitor(child)
  process.kill(parent)
  let assert Ok(_) =
    process.new_selector()
    |> process.select_specific_monitor(worker_monitor, fn(down) { down })
    |> process.selector_receive(5000)
  let assert Ok(_) =
    process.new_selector()
    |> process.select_specific_monitor(child_monitor, fn(down) { down })
    |> process.selector_receive(5000)
  process.demonitor_process(worker_monitor)
  process.demonitor_process(child_monitor)
  let assert Ok(client) = store.open_in(path)
  let assert Ok(note) = store.get_note(client, 1)
  assert note.body == "kept"
  let assert Ok(Nil) = store.close(client)
  let assert Ok(Nil) = simplifile.delete(path)
  helper.assert_no_protocol_leaks()
}
