pub fn set_exclusive_vm_contention_test() -> Nil {
  contention(Set)
}

pub fn bag_exclusive_vm_contention_test() -> Nil {
  contention(Bag)
}

pub fn duplicate_bag_exclusive_vm_contention_test() -> Nil {
  contention(DuplicateBag)
}

pub fn set_exclusive_vm_repeated_sessions_test() -> Nil {
  repeated_sessions(Set)
}

pub fn bag_exclusive_vm_repeated_sessions_test() -> Nil {
  repeated_sessions(Bag)
}

pub fn duplicate_bag_exclusive_vm_repeated_sessions_test() -> Nil {
  repeated_sessions(DuplicateBag)
}

pub fn exclusive_vm_owner_exit_test() -> Nil {
  owner_exit()
}

pub fn exclusive_vm_guardian_exit_test() -> Nil {
  guardian_exit()
}

pub fn exclusive_vm_callback_failures_test() -> Nil {
  callback_failures()
}

pub fn exclusive_vm_extra_user_test() -> Nil {
  extra_user()
}

pub fn exclusive_vm_crash_test() -> Nil {
  vm_crash()
}

pub fn exclusive_vm_aliases_test() -> Nil {
  aliases()
}

pub fn exclusive_vm_hard_links_test() -> Nil {
  hard_links()
}

pub fn exclusive_vm_different_files_test() -> Nil {
  different_files()
}

pub fn exclusive_vm_waiting_owner_exit_test() -> Nil {
  waiting_owner_exit()
}

pub fn exclusive_vm_open_owner_exit_test() -> Nil {
  open_exit(Owner)
}

pub fn exclusive_vm_open_guardian_exit_test() -> Nil {
  open_exit(Guardian)
}

pub fn exclusive_vm_close_owner_exit_test() -> Nil {
  close_exit(Owner)
}

pub fn exclusive_vm_close_guardian_exit_test() -> Nil {
  close_exit(Guardian)
}

pub fn exclusive_vm_cleanup_failures_test() -> Nil {
  cleanup_failures()
}

pub fn exclusive_vm_tmpfs_contention_test() -> Nil {
  tmpfs_contention()
}

pub fn exclusive_vm_unicode_paths_test() -> Nil {
  unicode_paths()
}

pub fn exclusive_vm_case_and_short_aliases_test() -> Nil {
  case_and_short_aliases()
}

pub fn exclusive_vm_repair_sidecar_test() -> Nil {
  repair_sidecar()
}

@external(erlang, "exclusive_vm_test_ffi", "unicode_paths")
fn unicode_paths() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "case_and_short_aliases")
fn case_and_short_aliases() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "repair_sidecar")
fn repair_sidecar() -> Nil

type TableType {
  Set
  Bag
  DuplicateBag
}

type KilledProcess {
  Owner
  Guardian
}

@external(erlang, "exclusive_vm_test_ffi", "open_exit")
fn open_exit(who: KilledProcess) -> Nil

@external(erlang, "exclusive_vm_test_ffi", "close_exit")
fn close_exit(who: KilledProcess) -> Nil

@external(erlang, "exclusive_vm_test_ffi", "cleanup_failures")
fn cleanup_failures() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "waiting_owner_exit")
fn waiting_owner_exit() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "tmpfs_contention")
fn tmpfs_contention() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "contention")
fn contention(table_type: TableType) -> Nil

@external(erlang, "exclusive_vm_test_ffi", "repeated_sessions")
fn repeated_sessions(table_type: TableType) -> Nil

@external(erlang, "exclusive_vm_test_ffi", "owner_exit")
fn owner_exit() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "guardian_exit")
fn guardian_exit() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "callback_failures")
fn callback_failures() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "extra_user")
fn extra_user() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "vm_crash")
fn vm_crash() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "aliases")
fn aliases() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "hard_links")
fn hard_links() -> Nil

@external(erlang, "exclusive_vm_test_ffi", "different_files")
fn different_files() -> Nil
