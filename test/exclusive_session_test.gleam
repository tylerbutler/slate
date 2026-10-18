import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import slate
import slate/exclusive
import slate/internal/exclusive_session
import slate/set
import test_helper

type CallbackValue {
  CallbackValue(items: List(Int), nested: Result(String, String))
}

pub fn exclusive_session_payload_stays_in_caller_test() -> Nil {
  let path = "test_exclusive_session_payload.dets"
  let value =
    CallbackValue(list.repeat(42, 20_000), Error("callback-owned-value"))
  let assert Ok(trace) = begin_trace()
  let result =
    set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(_) { Ok(value) },
    )
  let messages = end_trace(trace)
  test_helper.cleanup(path)
  cleanup_sidecar(path)
  assert result == Ok(value)
  // The result is a large list rather than just a ref-counted binary. Reject
  // either copying pass without depending on private protocol constructor tags.
  assert messages == True
}

pub fn exclusive_session_nested_result_test() -> Nil {
  let path = "test_exclusive_session_nested.dets"
  assert set.with_exclusive_table(
      path:,
      repair: slate.NoRepair,
      access: slate.ReadWrite,
      wait: exclusive.Immediate,
      key_decoder: decode.string,
      value_decoder: decode.int,
      callback: fn(_) { Ok(Error(CallbackValue([1, 2], Ok("nested")))) },
    )
    == Ok(Error(CallbackValue([1, 2], Ok("nested"))))
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_session_original_exception_test() -> Nil {
  let path = "test_exclusive_session_exception.dets"
  let assert Ok(trace) = begin_trace()
  assert check_original_exception(fn() {
      set.with_exclusive_table(
        path:,
        repair: slate.NoRepair,
        access: slate.ReadWrite,
        wait: exclusive.Immediate,
        key_decoder: decode.string,
        value_decoder: decode.int,
        callback: fn(_) { raise_original() },
      )
    })
    == True
  assert end_trace(trace) == True
  assert test_helper.is_table_open(path) == False
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_session_with_close_precedence_test() -> Nil {
  let value = Error(CallbackValue([42], Error("inner error")))
  assert exclusive_session.with_close(Nil, fn(_) { Ok(value) }, fn(_) {
      Ok(Nil)
    })
    == Ok(value)
  assert exclusive_session.with_close(Nil, fn(_) { Ok(value) }, fn(_) {
      Error(slate.TableDoesNotExist)
    })
    == Error(slate.TableDoesNotExist)
  assert exclusive_session.with_close(
      Nil,
      fn(_) { Error(slate.NotFound) },
      fn(_) { Ok(Nil) },
    )
    == Error(slate.NotFound)
  assert exclusive_session.with_close(
      Nil,
      fn(_) { Error(slate.NotFound) },
      fn(_) { Error(slate.TableDoesNotExist) },
    )
    == Error(slate.NotFound)
}

pub fn exclusive_session_with_close_original_exception_test() -> Nil {
  let attempts = process.new_subject()
  assert check_original_exception(fn() {
      exclusive_session.with_close(Nil, fn(_) { raise_original() }, fn(_) {
        process.send(attempts, Nil)
        raise_cleanup()
      })
    })
    == True
  assert process.receive(attempts, 0) == Ok(Nil)
  assert process.receive(attempts, 0) == Error(Nil)
}

pub fn exclusive_session_with_close_retries_raised_close_test() -> Nil {
  let attempts = process.new_subject()
  assert check_original_exception(fn() {
      exclusive_session.with_close(Nil, fn(_) { Ok(42) }, fn(_) {
        process.send(attempts, Nil)
        raise_original()
      })
    })
    == True
  assert process.receive(attempts, 0) == Ok(Nil)
  assert process.receive(attempts, 0) == Ok(Nil)
  assert process.receive(attempts, 0) == Error(Nil)
}

type Trace

@external(erlang, "exclusive_session_test_ffi", "begin_trace")
fn begin_trace() -> Result(Trace, Nil)

@external(erlang, "exclusive_session_test_ffi", "end_trace")
fn end_trace(trace: Trace) -> Bool

@external(erlang, "exclusive_session_test_ffi", "raise_original")
fn raise_original() -> Result(Nil, slate.DetsError)

@external(erlang, "exclusive_session_test_ffi", "raise_cleanup")
fn raise_cleanup() -> Result(Nil, slate.DetsError)

@external(erlang, "exclusive_session_test_ffi", "check_original_exception")
fn check_original_exception(callback: fn() -> a) -> Bool

@external(erlang, "exclusive_test_ffi", "cleanup_sidecar")
fn cleanup_sidecar(path: String) -> Nil
