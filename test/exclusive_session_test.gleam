import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import slate
import slate/exclusive
import slate/internal/exclusive_session
import slate/set
import startest/expect
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
  result |> expect.to_equal(Ok(value))
  // The result is a large list rather than just a ref-counted binary. Reject
  // either copying pass without depending on private protocol constructor tags.
  messages |> expect.to_equal(True)
}

pub fn exclusive_session_nested_result_test() -> Nil {
  let path = "test_exclusive_session_nested.dets"
  set.with_exclusive_table(
    path:,
    repair: slate.NoRepair,
    access: slate.ReadWrite,
    wait: exclusive.Immediate,
    key_decoder: decode.string,
    value_decoder: decode.int,
    callback: fn(_) { Ok(Error(CallbackValue([1, 2], Ok("nested")))) },
  )
  |> expect.to_equal(Ok(Error(CallbackValue([1, 2], Ok("nested")))))
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_session_original_exception_test() -> Nil {
  let path = "test_exclusive_session_exception.dets"
  let assert Ok(trace) = begin_trace()
  check_original_exception(fn() {
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
  |> expect.to_equal(True)
  end_trace(trace) |> expect.to_equal(True)
  test_helper.is_table_open(path) |> expect.to_equal(False)
  test_helper.cleanup(path)
  cleanup_sidecar(path)
}

pub fn exclusive_session_with_close_precedence_test() -> Nil {
  let value = Error(CallbackValue([42], Error("inner error")))
  exclusive_session.with_close(Nil, fn(_) { Ok(value) }, fn(_) { Ok(Nil) })
  |> expect.to_equal(Ok(value))
  exclusive_session.with_close(Nil, fn(_) { Ok(value) }, fn(_) {
    Error(slate.TableDoesNotExist)
  })
  |> expect.to_equal(Error(slate.TableDoesNotExist))
  exclusive_session.with_close(Nil, fn(_) { Error(slate.NotFound) }, fn(_) {
    Ok(Nil)
  })
  |> expect.to_equal(Error(slate.NotFound))
  exclusive_session.with_close(Nil, fn(_) { Error(slate.NotFound) }, fn(_) {
    Error(slate.TableDoesNotExist)
  })
  |> expect.to_equal(Error(slate.NotFound))
}

pub fn exclusive_session_with_close_original_exception_test() -> Nil {
  let attempts = process.new_subject()
  check_original_exception(fn() {
    exclusive_session.with_close(Nil, fn(_) { raise_original() }, fn(_) {
      process.send(attempts, Nil)
      raise_cleanup()
    })
  })
  |> expect.to_equal(True)
  process.receive(attempts, 0) |> expect.to_equal(Ok(Nil))
  process.receive(attempts, 0) |> expect.to_equal(Error(Nil))
}

pub fn exclusive_session_with_close_retries_raised_close_test() -> Nil {
  let attempts = process.new_subject()
  check_original_exception(fn() {
    exclusive_session.with_close(Nil, fn(_) { Ok(42) }, fn(_) {
      process.send(attempts, Nil)
      raise_original()
    })
  })
  |> expect.to_equal(True)
  process.receive(attempts, 0) |> expect.to_equal(Ok(Nil))
  process.receive(attempts, 0) |> expect.to_equal(Ok(Nil))
  process.receive(attempts, 0) |> expect.to_equal(Error(Nil))
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
