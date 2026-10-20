// Executed in disposable BEAM VMs so injection/quarantine cannot affect other
// tests. Calls go through the public Gleam Store API, never forged handles.
import dotes/store
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/string
import simplifile
import slate
import slate/exclusive
import store_test_helper as helper

pub fn run(fault: helper.Fault, path: String) -> Nil {
  helper.install(fault)
  case fault {
    helper.CleanupFailures -> cleanup_failures(path)
    helper.NestedStartupFailure -> nested_startup_failure(path)
    helper.RetryTags | helper.RetryHistory -> retry_delete(path, fault)
    helper.SerialUpdates -> serial_mutations(path, False)
    helper.UpdateThenDelete -> serial_mutations(path, True)
    helper.OwnerDiesDuringRequest -> owner_dies_during_request(path)
    helper.OwnerDiesDuringClose -> owner_dies_during_close(path)
    helper.OwnerDiesDuringStartup -> owner_dies_during_startup(path)
    helper.NativeUnavailable -> native_unavailable(path)
    helper.ParentDiesDuringCleanup -> parent_dies_during_cleanup(path)
    helper.WebBusy
    | helper.TuiStartupExit
    | helper.WebRuntimeExit
    | helper.TuiRuntimeExit -> helper.exercise_entrypoint(fault, path)
  }
  helper.assert_no_protocol_leaks()
}

fn seeded(path: String) -> store.Store {
  let assert Ok(client) = store.open_in(path)
  let assert Ok(1) = store.create_note(client, "title", "original")
  client
}

fn cleanup_failures(path: String) -> Nil {
  let client = seeded(path)
  let assert Error(store.Sessions(issues)) = store.close(client)
  assert list.map(issues, fn(issue) { issue.table })
    == [store.History, store.Tags]
  list.each(issues, fn(issue) {
    let assert exclusive.CleanupFailed(None, [exclusive.CloseFailure(_)]) =
      issue.error
    Nil
  })
  // The first close failure did not skip any of the other three sessions.
  assert helper.close_attempts()
    == ["history.dets", "tags.dets", "notes.dets", "counter.dets"]
  // Counter and notes really released; tags still fail closed. Never manually
  // close or remove quarantined resources: only this disposable VM's exit can.
  let assert Error(store.Sessions([
    store.SessionIssue(store.Tags, exclusive.AcquisitionFailed(exclusive.Busy)),
  ])) = store.open_in(path)
  assert helper.close_attempts() == ["notes.dets", "counter.dets"]
}

fn nested_startup_failure(path: String) -> Nil {
  let assert Ok(Nil) = simplifile.create_directory_all(path)
  let assert Ok(Nil) = simplifile.write(path <> "/notes.dets", "not DETS")
  let assert Error(
    store.Sessions([
      store.SessionIssue(
        store.Notes,
        exclusive.SessionFailed(exclusive.OpenFailure(slate.NotADetsFile(_))),
      ),
      store.SessionIssue(
        store.Counter,
        exclusive.CleanupFailed(None, [exclusive.CloseFailure(_)]),
      ),
    ]) as error,
  ) = store.open_in(path)
  let message = store.error_message(error)
  assert string.contains(message, "notes:")
  assert string.contains(message, "counter:")
  assert string.contains(message, "cleanup failed")
  assert !string.contains(message, "private-injected-diagnostic")
  assert helper.close_attempts() == ["counter.dets"]
  let assert Error(store.Sessions([
    store.SessionIssue(
      store.Counter,
      exclusive.AcquisitionFailed(exclusive.Busy),
    ),
  ])) = store.open_in(path)
  Nil
}

fn retry_delete(path: String, fault: helper.Fault) -> Nil {
  let client = seeded(path)
  let assert Ok(True) = store.toggle_tag(client, 1, "tag")
  let assert Ok(Nil) = store.update_note(client, 1, "updated")
  let assert Error(store.Storage(slate.AccessDenied(_))) =
    store.delete_note(client, 1)
  let assert Ok(note) = store.get_note(client, 1)
  assert note.body == "updated"
  let assert Ok([_]) = store.get_history(client, 1)
  assert store.get_tags(client, 1)
    == case fault {
      helper.RetryTags -> Ok(["tag"])
      _ -> Ok([])
    }
  let assert Ok(Nil) = store.delete_note(client, 1)
  assert store.get_note(client, 1) == Error(store.Storage(slate.NotFound))
  assert store.get_tags(client, 1) == Ok([])
  assert store.get_history(client, 1) == Ok([])
  assert store.delete_note(client, 1) == Error(store.Storage(slate.NotFound))
  let assert Ok(Nil) = store.close(client)
  Nil
}

fn serial_mutations(path: String, delete: Bool) -> Nil {
  let client = seeded(path)
  let first = process.new_subject()
  process.spawn_unlinked(fn() {
    process.send(first, store.update_note(client, 1, "A"))
  })
  // Pause precisely between reading the original and archiving it.
  let owner = helper.checkpoint()
  let second = process.new_subject()
  process.spawn_unlinked(fn() {
    let result = case delete {
      True -> store.delete_note(client, 1)
      False -> store.update_note(client, 1, "B")
    }
    process.send(second, result)
  })
  helper.await_queued(owner)
  assert process.receive(second, 0) == Error(Nil)
  helper.resume(owner)
  let assert Ok(Ok(Nil)) = process.receive(first, 5000)
  let assert Ok(Ok(Nil)) = process.receive(second, 5000)
  case delete {
    True -> {
      assert store.get_note(client, 1) == Error(store.Storage(slate.NotFound))
      assert store.get_history(client, 1) == Ok([])
      assert store.get_tags(client, 1) == Ok([])
      assert store.update_note(client, 1, "cannot resurrect")
        == Error(store.Storage(slate.NotFound))
    }
    False -> {
      let assert Ok(note) = store.get_note(client, 1)
      assert note.body == "B"
      let assert Ok(history) = store.get_history(client, 1)
      assert list.map(history, fn(r) { r.body }) |> list.sort(string.compare)
        == ["A", "original"]
    }
  }
  let assert Ok(Nil) = store.close(client)
  Nil
}

fn owner_dies_during_request(path: String) -> Nil {
  let client = seeded(path)
  let reply = process.new_subject()
  process.spawn_unlinked(fn() {
    process.send(reply, store.update_note(client, 1, "unknown"))
  })
  process.kill(helper.checkpoint())
  let assert Ok(Error(store.OwnerStopped(_))) = process.receive(reply, 5000)
  assert_dead(client)
  let next = helper.reacquire(path, 5000)
  let assert Ok(Nil) = store.close(next)
  Nil
}

fn owner_dies_during_close(path: String) -> Nil {
  let client = seeded(path)
  let assert Ok(Nil) = store.update_note(client, 1, "updated")
  let owner = helper.last_writer()
  let reply = process.new_subject()
  process.spawn_unlinked(fn() { process.send(reply, store.close(client)) })
  let guardian = helper.checkpoint()
  // Close has started, but acknowledgement must not precede cleanup.
  assert process.receive(reply, 0) == Error(Nil)
  process.kill(owner)
  let assert Ok(Error(store.OwnerStopped(_))) = process.receive(reply, 5000)
  helper.resume(guardian)
  assert_dead(client)
  let next = helper.reacquire(path, 5000)
  let assert Ok(Nil) = store.close(next)
  Nil
}

fn owner_dies_during_startup(path: String) -> Nil {
  let reply = process.new_subject()
  // This opener must remain alive after sending its result; otherwise it would
  // itself trigger parent-lifetime cleanup and obscure the owner-death check.
  let done = process.new_subject()
  process.spawn_unlinked(fn() {
    let stop = process.new_subject()
    process.send(done, stop)
    process.send(reply, store.open_in(path))
    process.receive_forever(stop)
  })
  let guardian = helper.checkpoint()
  process.kill(helper.opening_owner(guardian))
  let assert Ok(Error(store.OwnerStopped(_))) = process.receive(reply, 5000)
  helper.resume(guardian)
  let assert Ok(stop) = process.receive(done, 5000)
  process.send(stop, Nil)
  let next = helper.reacquire(path, 5000)
  let assert Ok(Nil) = store.close(next)
  Nil
}

fn native_unavailable(path: String) -> Nil {
  let assert Error(store.Sessions([
    store.SessionIssue(
      store.Counter,
      exclusive.AcquisitionFailed(exclusive.NativeUnavailable(_)),
    ),
  ])) = store.open_in(path)
  assert simplifile.is_file(path <> "/counter.dets") == Ok(False)
  Nil
}

fn assert_dead(client: store.Store) -> Nil {
  let assert Error(store.OwnerStopped(_)) = store.get_note(client, 1)
  let assert Error(store.OwnerStopped(_)) = store.close(client)
  Nil
}

fn parent_dies_during_cleanup(path: String) -> Nil {
  let output =
    helper.capture_output(fn() {
      let ready = process.new_subject()
      let parent =
        process.spawn_unlinked(fn() {
          let close = process.new_subject()
          let client = seeded(path)
          let assert Ok(Nil) = store.update_note(client, 1, "updated")
          process.send(ready, close)
          process.receive_forever(close)
          store.close(client)
        })
      let assert Ok(close) = process.receive(ready, 5000)
      let owner = helper.last_writer()
      let monitor = process.monitor(owner)
      process.send(close, Nil)
      let guardian = helper.checkpoint()
      let parent_monitor = process.monitor(parent)
      process.kill(parent)
      let assert Ok(_) =
        process.new_selector()
        |> process.select_specific_monitor(parent_monitor, fn(down) { down })
        |> process.selector_receive(5000)
      process.demonitor_process(parent_monitor)
      helper.resume(guardian)
      let assert Ok(_) =
        process.new_selector()
        |> process.select_specific_monitor(monitor, fn(down) { down })
        |> process.selector_receive(5000)
      process.demonitor_process(monitor)
      assert helper.close_attempts()
        == ["history.dets", "tags.dets", "notes.dets", "counter.dets"]
      // Failed tags remain quarantined, although counter and notes cleaned up.
      let assert Error(store.Sessions([
        store.SessionIssue(
          store.Tags,
          exclusive.AcquisitionFailed(exclusive.Busy),
        ),
      ])) = store.open_in(path)
      Nil
    })
  assert string.contains(output, "tags:")
  assert string.contains(output, "cleanup failed")
  assert !string.contains(output, "private-injected-diagnostic")
}
