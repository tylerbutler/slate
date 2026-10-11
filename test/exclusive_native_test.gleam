pub fn exclusive_native_owner_death_and_release_errors_test() -> Nil {
  owner_death()
}

pub fn exclusive_native_unsafe_sidecars_test() -> Nil {
  unsafe_sidecars()
}

pub fn exclusive_native_unsupported_filesystem_test() -> Nil {
  unsupported_filesystem()
}

@external(erlang, "exclusive_native_test_ffi", "owner_death")
fn owner_death() -> Nil

@external(erlang, "exclusive_native_test_ffi", "unsafe_sidecars")
fn unsafe_sidecars() -> Nil

@external(erlang, "exclusive_native_test_ffi", "unsupported_filesystem")
fn unsupported_filesystem() -> Nil

pub fn exclusive_native_os_failures_test() -> Nil {
  os_failures()
}

@external(erlang, "exclusive_native_test_ffi", "os_failures")
fn os_failures() -> Nil
