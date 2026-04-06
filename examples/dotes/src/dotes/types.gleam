import gleam/dynamic/decode
import gleam/time/calendar
import gleam/time/timestamp

/// A note with a title, body, and creation timestamp (Unix seconds).
pub type Note {
  Note(title: String, body: String, created_at: Int)
}

/// A historical revision of a note's body.
pub type Revision {
  Revision(body: String, edited_at: Int)
}

/// Decoder for Note values stored in DETS.
/// Gleam records are tagged tuples on the BEAM: {note, Title, Body, CreatedAt}
pub fn note_decoder() -> decode.Decoder(Note) {
  use title <- decode.field(1, decode.string)
  use body <- decode.field(2, decode.string)
  use created_at <- decode.field(3, decode.int)
  decode.success(Note(title:, body:, created_at:))
}

/// Decoder for Revision values stored in DETS.
/// Stored as: {revision, Body, EditedAt}
pub fn revision_decoder() -> decode.Decoder(Revision) {
  use body <- decode.field(1, decode.string)
  use edited_at <- decode.field(2, decode.int)
  decode.success(Revision(body:, edited_at:))
}

/// Format a Unix timestamp as a human-readable RFC 3339 UTC string.
pub fn format_timestamp(seconds: Int) -> String {
  timestamp.from_unix_seconds(seconds)
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

/// Get the current time as Unix seconds.
pub fn now() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds()
  seconds
}
