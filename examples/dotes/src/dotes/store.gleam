import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/time/calendar
import gleam/time/timestamp
import simplifile
import slate
import slate/bag
import slate/duplicate_bag
import slate/set

/// A note with a title, body, and creation timestamp (Unix seconds).
pub type Note {
  Note(title: String, body: String, created_at: Int)
}

/// A historical revision of a note's body.
pub type Revision {
  Revision(body: String, edited_at: Int)
}

/// Decoder for Note values stored as {note, Title, Body, CreatedAt}.
fn note_decoder() -> decode.Decoder(Note) {
  use title <- decode.field(1, decode.string)
  use body <- decode.field(2, decode.string)
  use created_at <- decode.field(3, decode.int)
  decode.success(Note(title:, body:, created_at:))
}

/// Decoder for Revision values stored as {revision, Body, EditedAt}.
fn revision_decoder() -> decode.Decoder(Revision) {
  use body <- decode.field(1, decode.string)
  use edited_at <- decode.field(2, decode.int)
  decode.success(Revision(body:, edited_at:))
}

/// Convert Unix seconds to an RFC 3339 UTC string.
pub fn unix_seconds_to_rfc3339(seconds: Int) -> String {
  timestamp.from_unix_seconds(seconds)
  |> timestamp.to_rfc3339(calendar.utc_offset)
}

fn now() -> Int {
  let #(seconds, _nanoseconds) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds()
  seconds
}

/// All four DETS tables used by dotes.
pub type Store {
  Store(
    counter: set.Set(String, Int),
    notes: set.Set(Int, Note),
    tags: bag.Bag(Int, String),
    history: duplicate_bag.DuplicateBag(Int, Revision),
  )
}

const data_directory = ".dotes"

/// Open all four tables, creating the data directory if needed.
pub fn open() -> Result(Store, slate.DetsError) {
  let _ = simplifile.create_directory(data_directory)
  use counter <- result.try(set.open(
    data_directory <> "/counter.dets",
    key_decoder: decode.string,
    value_decoder: decode.int,
  ))
  use notes <- result.try(set.open(
    data_directory <> "/notes.dets",
    key_decoder: decode.int,
    value_decoder: note_decoder(),
  ))
  use tags <- result.try(bag.open(
    data_directory <> "/tags.dets",
    key_decoder: decode.int,
    value_decoder: decode.string,
  ))
  use history <- result.try(duplicate_bag.open(
    data_directory <> "/history.dets",
    key_decoder: decode.int,
    value_decoder: revision_decoder(),
  ))
  Ok(Store(counter:, notes:, tags:, history:))
}

/// Close all four tables, flushing data to disk.
pub fn close(store: Store) -> Result(Nil, slate.DetsError) {
  use _ <- result.try(set.close(store.counter))
  use _ <- result.try(set.close(store.notes))
  use _ <- result.try(bag.close(store.tags))
  duplicate_bag.close(store.history)
}

/// Generate the next note ID using an atomic counter.
fn next_id(store: Store) -> Result(Int, slate.DetsError) {
  // update_counter requires the key to already exist. insert_new is a no-op
  // if the key is already present, so this safely seeds the counter only once.
  let _ = set.insert_new(store.counter, "next_id", 0)
  case set.update_counter(store.counter, "next_id", 1) {
    Ok(id) -> Ok(id)
    Error(set.TableError(e)) -> Error(e)
    Error(set.CounterValueNotInteger) ->
      Error(slate.UnexpectedError("Counter value is not an integer"))
  }
}

/// Create a new note. Returns the assigned ID.
pub fn create_note(
  store: Store,
  title title: String,
  body body: String,
) -> Result(Int, slate.DetsError) {
  use id <- result.try(next_id(store))
  let note = Note(title:, body:, created_at: now())
  use _ <- result.try(set.insert_new(store.notes, id, note))
  Ok(id)
}

/// Update an existing note's body, archiving the previous version.
pub fn update_note(
  store: Store,
  id id: Int,
  body body: String,
) -> Result(Nil, slate.DetsError) {
  use current <- result.try(set.lookup(store.notes, key: id))
  let revision = Revision(body: current.body, edited_at: now())
  use _ <- result.try(duplicate_bag.insert(store.history, id, revision))
  let updated = Note(..current, body:)
  set.insert(store.notes, id, updated)
}

/// Look up a single note by ID.
pub fn get_note(store: Store, id: Int) -> Result(Note, slate.DetsError) {
  set.lookup(store.notes, key: id)
}

/// List all notes as (id, note) pairs, sorted by ID.
pub fn list_notes(store: Store) -> Result(List(#(Int, Note)), slate.DetsError) {
  use notes <- result.try(
    set.fold(store.notes, [], fn(acc, id, note) { [#(id, note), ..acc] }),
  )
  Ok(
    list.sort(notes, by: fn(a, b) {
      let #(id_a, _) = a
      let #(id_b, _) = b
      int.compare(id_a, id_b)
    }),
  )
}

/// Get all tags for a note.
pub fn get_tags(
  store: Store,
  id: Int,
) -> Result(List(String), slate.DetsError) {
  bag.lookup(store.tags, key: id)
}

/// Get edit history for a note.
pub fn get_history(
  store: Store,
  id: Int,
) -> Result(List(Revision), slate.DetsError) {
  duplicate_bag.lookup(store.history, key: id)
}

/// Toggle a tag on a note. Returns True if added, False if removed.
pub fn toggle_tag(
  store: Store,
  id id: Int,
  tag tag: String,
) -> Result(Bool, slate.DetsError) {
  // DETS delete is a no-op on missing keys; lookup first so we return
  // NotFound rather than silently succeeding on a ghost note.
  use _ <- result.try(set.lookup(store.notes, key: id))
  use current_tags <- result.try(bag.lookup(store.tags, key: id))
  case list.contains(current_tags, tag) {
    True -> {
      use _ <- result.try(bag.delete_object(store.tags, id, tag))
      Ok(False)
    }
    False -> {
      use _ <- result.try(bag.insert(store.tags, id, tag))
      Ok(True)
    }
  }
}

/// Delete a note and all its associated tags and history.
pub fn delete_note(store: Store, id: Int) -> Result(Nil, slate.DetsError) {
  // DETS delete_key is a no-op when the key is absent, so lookup first to
  // return NotFound for a missing note rather than reporting success.
  use _ <- result.try(set.lookup(store.notes, key: id))
  use _ <- result.try(set.delete_key(store.notes, id))
  use _ <- result.try(bag.delete_key(store.tags, id))
  duplicate_bag.delete_key(store.history, id)
}
