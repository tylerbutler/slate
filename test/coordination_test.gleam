//// Queue lifecycle checks that require OTP process and monitor inspection.

pub fn monitored_queue_lifecycle_test() -> Nil {
  run()
}

pub fn coordination_failure_blocks_restart_test() -> Nil {
  failure()
}

@external(erlang, "coordination_test_ffi", "run")
fn run() -> Nil

@external(erlang, "coordination_test_ffi", "failure")
fn failure() -> Nil
