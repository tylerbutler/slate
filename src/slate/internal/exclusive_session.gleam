//// Internal exclusive-session protocol. The guardian owns DETS and native
//// ownership; the caller owns callback values and original exception stacks.

import gleam/erlang/process.{
  type Down, type ExitReason, type Monitor, type Pid, type Selector,
  type Subject,
}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import slate.{type DetsError}
import slate/exclusive.{
  type CleanupFailure, type LockError, type SessionError, type SessionFailure,
}

/// An existing DETS handle: a pooled atom or the allocator's exclusive tag.
/// Never convert this opaque value to a Gleam record or an unvalidated Pid.
pub type TableHandle

type TableName

type LockToken

type Exception

type ExceptionMetadata

type Captured(a) {
  Returned(a)
  Raised(Exception, ExceptionMetadata)
}

type Deadline {
  TryImmediately
  Until(milliseconds: Int)
}

// Deliberately contains neither a successful payload nor an exception stack.
type Completion {
  Succeeded
  Failed(DetsError)
  Threw(ExceptionMetadata)
}

type Channels {
  Channels(
    begin: Subject(Nil),
    finish: Subject(Completion),
    received: Subject(Nil),
  )
}

type Caller {
  Caller(
    startup: Subject(Channels),
    opened: Subject(Result(TableHandle, SessionError)),
    finished: Subject(Result(Nil, SessionError)),
  )
}

type GuardianContext {
  GuardianContext(
    caller: Caller,
    channels: Channels,
    owner_monitor: Monitor,
    path: String,
  )
}

type Monitored(a) {
  Message(a)
  Stopped(ExitReason)
}

/// Run close-on-exit in the caller, preserving the ordinary with_table contract.
pub fn with_close(
  resource: resource,
  callback: fn(resource) -> Result(a, DetsError),
  close: fn(resource) -> Result(Nil, DetsError),
) -> Result(a, DetsError) {
  case
    capture(fn() {
      let callback_result = callback(resource)
      let close_result = close(resource)
      case callback_result, close_result {
        Ok(value), Ok(Nil) -> Ok(value)
        Ok(_), Error(error) -> Error(error)
        Error(error), Ok(Nil) | Error(error), Error(_) -> Error(error)
      }
    })
  {
    Returned(value) -> value
    Raised(exception, _) -> {
      // Match the existing best-effort retry even if close itself raised.
      let _attempt = capture(fn() { close(resource) })
      reraise(exception)
    }
  }
}

/// Acquire, open in the guardian, run the callback in the caller, then clean up.
pub fn with_table(
  path: String,
  wait: exclusive.Wait,
  open: fn(String) -> Result(TableHandle, DetsError),
  callback: fn(TableHandle) -> Result(a, DetsError),
) -> Result(a, SessionError) {
  use deadline <- result.try(
    deadline(wait) |> result.map_error(exclusive.AcquisitionFailed),
  )
  let caller =
    Caller(process.new_subject(), process.new_subject(), process.new_subject())
  let owner = process.self()
  // Do not capture callback here: copying its closure could also copy a payload.
  let guardian =
    process.spawn_unlinked(fn() {
      guardian(owner, caller, path, deadline, open)
    })
  let monitor = process.monitor(guardian)
  case await(caller.startup, monitor) {
    Stopped(reason) -> Error(stopped(None, reason))
    Message(channels) -> {
      // Establish the caller monitor before the guardian can acquire anything.
      process.send(channels.begin, Nil)
      case await(caller.opened, monitor) {
        Stopped(reason) -> Error(stopped(None, reason))
        Message(Error(error)) -> {
          acknowledge(channels, monitor)
          Error(error)
        }
        Message(Ok(table)) -> {
          let outcome = capture(fn() { callback(table) })
          let completion = case outcome {
            Returned(Ok(_)) -> Succeeded
            Returned(Error(error)) -> Failed(error)
            Raised(_, metadata) -> Threw(metadata)
          }
          process.send(channels.finish, completion)
          let cleanup_result = case await(caller.finished, monitor) {
            Message(reply) -> {
              acknowledge(channels, monitor)
              reply
            }
            Stopped(reason) -> Error(stopped(primary(completion), reason))
          }
          case outcome {
            Raised(exception, _) -> reraise(exception)
            Returned(callback_result) ->
              case cleanup_result {
                Error(error) -> Error(error)
                Ok(Nil) ->
                  // Construct the Result locally; never flatten generic values.
                  callback_result
                  |> result.map_error(fn(error) {
                    exclusive.SessionFailed(exclusive.CallbackFailure(error))
                  })
              }
          }
        }
      }
    }
  }
}

fn acknowledge(channels: Channels, monitor: Monitor) -> Nil {
  process.send(channels.received, Nil)
  process.demonitor_process(monitor)
}

fn deadline(wait: exclusive.Wait) -> Result(Deadline, LockError) {
  case wait {
    exclusive.Immediate | exclusive.WaitUpTo(0) -> Ok(TryImmediately)
    exclusive.WaitUpTo(milliseconds) if milliseconds > 0 ->
      Ok(Until(now() + milliseconds))
    exclusive.WaitUpTo(milliseconds) ->
      Error(exclusive.InvalidWait(milliseconds))
  }
}

fn expired(deadline: Deadline) -> Bool {
  case deadline {
    TryImmediately -> False
    Until(milliseconds) -> now() >= milliseconds
  }
}

fn retry_delay(deadline: Deadline) -> Int {
  case deadline {
    TryImmediately -> 0
    Until(milliseconds) -> int.min(20, int.max(0, milliseconds - now()))
  }
}

fn primary(completion: Completion) -> Option(SessionFailure) {
  case completion {
    Succeeded | Threw(_) -> None
    Failed(error) -> Some(exclusive.CallbackFailure(error))
  }
}

fn finalize(
  primary: Option(SessionFailure),
  failures: List(CleanupFailure),
) -> Result(Nil, SessionError) {
  case failures, primary {
    [], None -> Ok(Nil)
    [], Some(failure) -> Error(exclusive.SessionFailed(failure))
    [_, ..], primary -> Error(exclusive.CleanupFailed(primary, failures))
  }
}

fn failure_error(
  failure: SessionFailure,
  failures: List(CleanupFailure),
) -> SessionError {
  case failures {
    [] -> exclusive.SessionFailed(failure)
    [_, ..] -> exclusive.CleanupFailed(Some(failure), failures)
  }
}

fn stopped(
  primary: Option(SessionFailure),
  reason: ExitReason,
) -> SessionError {
  exclusive.CleanupFailed(primary, [
    exclusive.GuardianStopped(exit_detail(reason)),
  ])
}

fn down_reason(down: Down) -> ExitReason {
  case down {
    process.ProcessDown(_, _, reason) | process.PortDown(_, _, reason) -> reason
  }
}

fn selector(subject: Subject(a), monitor: Monitor) -> Selector(Monitored(a)) {
  process.new_selector()
  |> process.select_map(subject, Message)
  |> process.select_specific_monitor(monitor, fn(down) {
    Stopped(down_reason(down))
  })
}

fn await(subject: Subject(a), monitor: Monitor) -> Monitored(a) {
  selector(subject, monitor) |> process.selector_receive_forever
}

fn owner_selector(monitor: Monitor) -> Selector(ExitReason) {
  process.new_selector()
  |> process.select_specific_monitor(monitor, down_reason)
}

fn guardian(
  owner: Pid,
  caller: Caller,
  path: String,
  deadline: Deadline,
  open: fn(String) -> Result(TableHandle, DetsError),
) -> Nil {
  let owner_monitor = process.monitor(owner)
  let channels =
    Channels(
      process.new_subject(),
      process.new_subject(),
      process.new_subject(),
    )
  let context = GuardianContext(caller, channels, owner_monitor, path)
  case watch_guardian(path) {
    Error(reason) -> {
      process.send(caller.opened, Error(stopped(None, reason)))
      // Also unblock startup; the caller acknowledges the opened error.
      process.send(caller.startup, channels)
      delivery(context, Error(stopped(None, reason)))
    }
    Ok(Nil) -> {
      process.send(caller.startup, channels)
      case await(channels.begin, owner_monitor) {
        Stopped(_) -> Nil
        Message(Nil) ->
          case ensure_loaded() {
            Error(error) ->
              reply_open_error(context, exclusive.AcquisitionFailed(error))
            Ok(Nil) -> acquire(context, deadline, open)
          }
      }
    }
  }
}

fn watch_guardian(path: String) -> Result(Nil, ExitReason) {
  let guardian = process.self()
  let watching = process.new_subject()
  let watcher =
    process.spawn_unlinked(fn() {
      let monitor = process.monitor(guardian)
      process.send(watching, Nil)
      case owner_selector(monitor) |> process.selector_receive_forever {
        process.Normal -> Nil
        process.Killed -> log_guardian_stopped(path, process.Killed)
        process.Abnormal(reason) ->
          log_guardian_stopped(path, process.Abnormal(reason))
      }
    })
  let monitor = process.monitor(watcher)
  let result = case await(watching, monitor) {
    Message(Nil) -> Ok(Nil)
    Stopped(reason) -> Error(reason)
  }
  process.demonitor_process(monitor)
  result
}

fn acquire(
  context: GuardianContext,
  deadline: Deadline,
  open: fn(String) -> Result(TableHandle, DetsError),
) -> Nil {
  case owner_selector(context.owner_monitor) |> process.selector_receive(0) {
    Ok(_) -> Nil
    Error(Nil) ->
      case expired(deadline) {
        True ->
          reply_open_error(
            context,
            exclusive.AcquisitionFailed(exclusive.TimedOut),
          )
        False ->
          case acquire_lock(context.path) {
            Ok(#(token, canonical_path)) ->
              case expired(deadline) {
                True -> {
                  let failures = release(token)
                  let error = case failures {
                    [] -> exclusive.AcquisitionFailed(exclusive.TimedOut)
                    [_, ..] ->
                      failure_error(
                        exclusive.AcquisitionFailure(exclusive.TimedOut),
                        failures,
                      )
                  }
                  reply_open_error(context, error)
                }
                False ->
                  owned(
                    GuardianContext(..context, path: canonical_path),
                    token,
                    open,
                  )
              }
            Error(exclusive.Busy) ->
              case deadline {
                TryImmediately ->
                  reply_open_error(
                    context,
                    exclusive.AcquisitionFailed(exclusive.Busy),
                  )
                Until(_) ->
                  case
                    owner_selector(context.owner_monitor)
                    |> process.selector_receive(retry_delay(deadline))
                  {
                    Ok(_) -> Nil
                    Error(Nil) -> acquire(context, deadline, open)
                  }
              }
            Error(error) ->
              reply_open_error(context, exclusive.AcquisitionFailed(error))
          }
      }
  }
}

fn owned(
  context: GuardianContext,
  token: LockToken,
  open: fn(String) -> Result(TableHandle, DetsError),
) -> Nil {
  case owner_selector(context.owner_monitor) |> process.selector_receive(0) {
    Ok(reason) -> owner_cleanup(context.path, release(token), reason)
    Error(Nil) -> {
      let opened = case existing_table(context.path, all_tables()) {
        Error(error) -> Error(error)
        Ok(True) ->
          Error(
            slate.AlreadyOpen(slate.FileErrorContext(
              Some(context.path),
              "incompatible_arguments",
            )),
          )
        Ok(False) -> open(context.path)
      }
      case opened {
        Error(error) ->
          reply_open_error(
            context,
            failure_error(exclusive.OpenFailure(error), release(token)),
          )
        Ok(table) -> {
          let table_process = table_pid(table)
          let table_monitor = process.monitor(table_process)
          case
            owner_selector(context.owner_monitor) |> process.selector_receive(0)
          {
            Ok(reason) ->
              owner_cleanup(
                context.path,
                cleanup(table, table_process, table_monitor, token),
                reason,
              )
            Error(Nil) -> {
              process.send(context.caller.opened, Ok(table))
              case await(context.channels.finish, context.owner_monitor) {
                Stopped(reason) ->
                  owner_cleanup(
                    context.path,
                    cleanup(table, table_process, table_monitor, token),
                    reason,
                  )
                Message(completion) -> {
                  let reply =
                    finalize(
                      primary(completion),
                      cleanup(table, table_process, table_monitor, token),
                    )
                  case completion, reply {
                    Threw(metadata), Error(error) ->
                      log_exception_cleanup(context.path, error, metadata)
                    Threw(_), Ok(Nil) | Succeeded, _ | Failed(_), _ -> Nil
                  }
                  process.send(context.caller.finished, reply)
                  delivery(context, reply)
                }
              }
            }
          }
        }
      }
    }
  }
}

fn cleanup(
  table: TableHandle,
  table_process: Pid,
  table_monitor: Monitor,
  token: LockToken,
) -> List(CleanupFailure) {
  case close(table) {
    Error(error) -> {
      process.demonitor_process(table_monitor)
      [exclusive.CloseFailure(error)]
    }
    Ok(Nil) ->
      case still_open(table, table_process) {
        True -> {
          process.demonitor_process(table_monitor)
          [
            exclusive.CloseFailure(slate.UnexpectedError(
              "exclusive_table_still_open",
            )),
          ]
        }
        False -> {
          // Never release on close's return alone. DOWN confirms the server
          // can no longer write. No timeout: uncertainty quarantines the lock.
          let _reason =
            owner_selector(table_monitor) |> process.selector_receive_forever
          release(token)
        }
      }
  }
}

fn existing_table(
  path: String,
  tables: List(TableName),
) -> Result(Bool, DetsError) {
  case tables {
    [] -> Ok(False)
    [table, ..rest] ->
      case table_filename(table) {
        Error(Nil) -> existing_table(path, rest)
        Ok(filename) ->
          case resolve_path(filename) {
            Ok(canonical_path) if canonical_path == path -> Ok(True)
            Ok(_) -> existing_table(path, rest)
            Error(error) ->
              Error(slate.UnexpectedError(lock_error_detail(error)))
          }
      }
  }
}

fn release(token: LockToken) -> List(CleanupFailure) {
  case release_lock(token) {
    Ok(Nil) -> []
    Error(error) -> [exclusive.ReleaseFailure(error)]
  }
}

fn owner_cleanup(
  path: String,
  failures: List(CleanupFailure),
  reason: ExitReason,
) -> Nil {
  case failures {
    [] -> Nil
    [_, ..] -> log_owner_cleanup(path, failures, reason)
  }
}

fn reply_open_error(context: GuardianContext, error: SessionError) -> Nil {
  process.send(context.caller.opened, Error(error))
  delivery(context, Error(error))
}

fn delivery(context: GuardianContext, reply: Result(Nil, SessionError)) -> Nil {
  // Cleanup errors must reach either the caller or Logger, including when
  // the owner dies after finish but before consuming the cleanup result.
  case await(context.channels.received, context.owner_monitor) {
    Message(Nil) -> Nil
    Stopped(reason) ->
      case reply {
        Error(exclusive.CleanupFailed(_, _) as error) ->
          log_undelivered(context.path, error, reason)
        Ok(Nil)
        | Error(exclusive.AcquisitionFailed(_))
        | Error(exclusive.SessionFailed(_)) -> Nil
      }
  }
}

type TimeUnit {
  Millisecond
}

// gleam_erlang 1.3 has sleep/timers but no monotonic clock API.
@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: TimeUnit) -> Int

fn now() -> Int {
  monotonic_time(Millisecond)
}

@external(erlang, "slate_lock_nif", "ensure_loaded")
fn ensure_loaded() -> Result(Nil, LockError)

@external(erlang, "slate_lock_nif", "acquire")
fn acquire_lock(path: String) -> Result(#(LockToken, String), LockError)

@external(erlang, "slate_lock_nif", "release")
fn release_lock(token: LockToken) -> Result(Nil, LockError)

@external(erlang, "slate_lock_nif", "resolve")
fn resolve_path(path: String) -> Result(String, LockError)

@external(erlang, "slate_dets_ffi", "close")
fn close(table: TableHandle) -> Result(Nil, DetsError)

@external(erlang, "dets", "all")
fn all_tables() -> List(TableName)

@external(erlang, "slate_exclusive_table_ffi", "table_filename")
fn table_filename(table: TableName) -> Result(String, Nil)

@external(erlang, "slate_exclusive_table_ffi", "table_pid")
fn table_pid(table: TableHandle) -> Pid

@external(erlang, "slate_exclusive_table_ffi", "still_open")
fn still_open(table: TableHandle, pid: Pid) -> Bool

@external(erlang, "slate_with_table_ffi", "capture")
fn capture(callback: fn() -> a) -> Captured(a)

@external(erlang, "slate_with_table_ffi", "reraise")
fn reraise(exception: Exception) -> a

@external(erlang, "slate_exclusive_table_ffi", "lock_error_detail")
fn lock_error_detail(error: LockError) -> String

@external(erlang, "slate_exclusive_table_ffi", "exit_detail")
fn exit_detail(reason: ExitReason) -> String

@external(erlang, "slate_exclusive_table_ffi", "log_guardian_stopped")
fn log_guardian_stopped(path: String, reason: ExitReason) -> Nil

@external(erlang, "slate_exclusive_table_ffi", "log_owner_cleanup")
fn log_owner_cleanup(
  path: String,
  failures: List(CleanupFailure),
  reason: ExitReason,
) -> Nil

@external(erlang, "slate_exclusive_table_ffi", "log_undelivered")
fn log_undelivered(path: String, error: SessionError, reason: ExitReason) -> Nil

@external(erlang, "slate_exclusive_table_ffi", "log_exception_cleanup")
fn log_exception_cleanup(
  path: String,
  error: SessionError,
  metadata: ExceptionMetadata,
) -> Nil
