import gleam/option.{Some}
import slate

/// Expected context for operations that open a canonical path.
pub fn context(path: String, reason: String) -> slate.FileErrorContext {
  slate.FileErrorContext(path: Some(absolute_path(path)), reason:)
}

@external(erlang, "file_error_test_ffi", "absolute_path")
fn absolute_path(path: String) -> String
