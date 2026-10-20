import dotes/store
import gleam/erlang/process
import gleam/int
import simplifile

pub type Fault {
  CleanupFailures
  NestedStartupFailure
  RetryTags
  RetryHistory
  SerialUpdates
  UpdateThenDelete
  OwnerDiesDuringRequest
  OwnerDiesDuringClose
  OwnerDiesDuringStartup
  NativeUnavailable
  ParentDiesDuringCleanup
  WebBusy
  TuiStartupExit
  WebRuntimeExit
  TuiRuntimeExit
}

pub fn directory() -> String {
  "build/store-test-" <> int.to_string(unique_integer())
}

pub fn with_store(run: fn(store.Store, String) -> Nil) -> Nil {
  let path = directory()
  let assert Ok(client) = store.open_in(path)
  run(client, path)
  let assert Ok(Nil) = store.close(client)
  let assert Ok(Nil) = simplifile.delete(path)
  Nil
}

// Only acquisition is retried, never a write with unknown outcome.
pub fn reacquire(path: String, remaining: Int) -> store.Store {
  case store.open_in(path) {
    Ok(client) -> client
    Error(error) -> {
      assert remaining > 0 as store.error_message(error)
      process.sleep(1)
      reacquire(path, remaining - 1)
    }
  }
}

pub fn await_stopped(client: store.Store, remaining: Int) -> Nil {
  case store.get_note(client, 1) {
    Error(store.OwnerStopped(_)) -> Nil
    Ok(_) -> {
      assert remaining > 0 as "Store outlived its parent"
      process.sleep(1)
      await_stopped(client, remaining - 1)
    }
    Error(error) -> panic as store.error_message(error)
  }
}

// Test-only FFI: launching private VMs and rewriting BEAM external calls are
// deliberately not production APIs and have no typed dependency equivalent.
@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

@external(erlang, "store_test_ffi", "contention")
pub fn contention(directory: String) -> Nil

@external(erlang, "store_test_ffi", "run_case")
pub fn run_case(fault: Fault, directory: String) -> Nil

@external(erlang, "store_test_ffi", "install")
pub fn install(fault: Fault) -> Nil

@external(erlang, "store_test_ffi", "checkpoint")
pub fn checkpoint() -> process.Pid

@external(erlang, "store_test_ffi", "resume")
pub fn resume(pid: process.Pid) -> Nil

@external(erlang, "store_test_ffi", "last_writer")
pub fn last_writer() -> process.Pid

@external(erlang, "store_test_ffi", "opening_owner")
pub fn opening_owner(guardian: process.Pid) -> process.Pid

@external(erlang, "store_test_ffi", "await_queued")
pub fn await_queued(owner: process.Pid) -> Nil

@external(erlang, "store_test_ffi", "close_attempts")
pub fn close_attempts() -> List(String)

@external(erlang, "store_test_ffi", "assert_no_protocol_leaks")
pub fn assert_no_protocol_leaks() -> Nil

@external(erlang, "store_test_ffi", "capture_output")
pub fn capture_output(run: fn() -> Nil) -> String

@external(erlang, "entrypoint_test_ffi", "exercise")
pub fn exercise_entrypoint(fault: Fault, directory: String) -> Nil
